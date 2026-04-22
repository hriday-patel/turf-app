import crypto from "node:crypto";
import { supabase } from "../_utils/supabase.js";
import { applyCors } from "../_utils/cors.js";

// S8: Fail loudly at module load if STORAGE_BUCKET is missing or malformed.
// No silent fallback — a misconfigured deploy must not silently write to the
// wrong bucket.
const STORAGE_BUCKET = (() => {
  const raw = String(process.env.STORAGE_BUCKET || "").trim();
  if (!raw || raw === "STORAGE_BUCKET") {
    throw new Error(
      "STORAGE_BUCKET env var is required (must be a plain bucket name).",
    );
  }
  if (raw.includes("://") || raw.includes("/")) {
    throw new Error(
      "STORAGE_BUCKET env var must be a bucket name, not a URL or path.",
    );
  }
  return raw;
})();

// S5: Hard cap on decoded image size (matches the 5 MB bucket policy).
const MAX_DECODED_BYTES = 5 * 1024 * 1024;

// S5: Best-effort per-IP rate limit. Note: serverless instances are isolated
// so this is per-instance, not global. Sufficient as a first line of defence;
// pair with platform-level WAF / Vercel rate limits in production.
const RATE_LIMIT_MAX = 20;
const RATE_LIMIT_WINDOW_MS = 10 * 60 * 1000;
const rateLimitMap = new Map();

function checkRateLimit(ip) {
  const now = Date.now();
  const entry = rateLimitMap.get(ip);
  if (!entry || now - entry.windowStart > RATE_LIMIT_WINDOW_MS) {
    rateLimitMap.set(ip, { count: 1, windowStart: now });
    return true;
  }
  entry.count += 1;
  return entry.count <= RATE_LIMIT_MAX;
}

function getClientIp(req) {
  const fwd = req.headers["x-forwarded-for"];
  if (typeof fwd === "string" && fwd.length) {
    return fwd.split(",")[0].trim();
  }
  return req.socket?.remoteAddress || "unknown";
}

// S4: Magic-byte sniffing. Only real JPEG/PNG/WebP are accepted; SVG and
// every other type is rejected. The detected type also overrides whatever
// the client claimed in `contentType`.
function detectImageType(buf) {
  if (
    buf.length >= 3 &&
    buf[0] === 0xff &&
    buf[1] === 0xd8 &&
    buf[2] === 0xff
  ) {
    return { ext: "jpg", contentType: "image/jpeg" };
  }
  if (
    buf.length >= 8 &&
    buf[0] === 0x89 &&
    buf[1] === 0x50 &&
    buf[2] === 0x4e &&
    buf[3] === 0x47 &&
    buf[4] === 0x0d &&
    buf[5] === 0x0a &&
    buf[6] === 0x1a &&
    buf[7] === 0x0a
  ) {
    return { ext: "png", contentType: "image/png" };
  }
  if (
    buf.length >= 12 &&
    buf[0] === 0x52 &&
    buf[1] === 0x49 &&
    buf[2] === 0x46 &&
    buf[3] === 0x46 &&
    buf[8] === 0x57 &&
    buf[9] === 0x45 &&
    buf[10] === 0x42 &&
    buf[11] === 0x50
  ) {
    return { ext: "webp", contentType: "image/webp" };
  }
  return null;
}

const UUID_RE =
  /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

export const config = {
  api: {
    bodyParser: {
      sizeLimit: "10mb",
    },
  },
};

export default async function handler(req, res) {
  if (applyCors(req, res)) return;

  if (req.method !== "POST") {
    return res
      .status(405)
      .json({ error: "Method not allowed", code: "METHOD_NOT_ALLOWED" });
  }

  // S5: rate limit
  const ip = getClientIp(req);
  if (!checkRateLimit(ip)) {
    return res
      .status(429)
      .json({ error: "Too many uploads", code: "RATE_LIMITED" });
  }

  // S1: require a Supabase Bearer token and resolve the user.
  const authHeader = req.headers.authorization || "";
  const token = authHeader.startsWith("Bearer ")
    ? authHeader.slice(7).trim()
    : "";
  if (!token) {
    return res
      .status(401)
      .json({ error: "Authentication required", code: "AUTH_REQUIRED" });
  }

  let userId;
  try {
    const { data: userData, error: userErr } =
      await supabase.auth.getUser(token);
    if (userErr || !userData?.user?.id) {
      return res
        .status(401)
        .json({ error: "Invalid token", code: "AUTH_INVALID" });
    }
    userId = userData.user.id;
  } catch (e) {
    console.error("Auth lookup failed:", e);
    return res
      .status(401)
      .json({ error: "Invalid token", code: "AUTH_INVALID" });
  }

  try {
    const { imageData, turfId } = req.body || {};

    if (!imageData || !turfId) {
      return res.status(400).json({
        error: "Missing required fields: imageData, turfId",
        code: "MISSING_FIELDS",
      });
    }
    if (typeof turfId !== "string" || !UUID_RE.test(turfId)) {
      return res
        .status(400)
        .json({ error: "Invalid turfId", code: "INVALID_TURF_ID" });
    }
    if (typeof imageData !== "string") {
      return res
        .status(400)
        .json({ error: "Invalid imageData", code: "INVALID_DATA" });
    }

    // S1 + S2: confirm the caller owns the turf they're uploading for.
    const { data: turfRow, error: turfErr } = await supabase
      .from("turfs")
      .select("id, owner_id")
      .eq("id", turfId)
      .maybeSingle();

    if (turfErr) {
      console.error("Turf lookup error:", turfErr);
      return res
        .status(500)
        .json({ error: "Lookup failed", code: "TURF_LOOKUP" });
    }
    if (!turfRow) {
      return res
        .status(404)
        .json({ error: "Turf not found", code: "TURF_NOT_FOUND" });
    }
    if (turfRow.owner_id !== userId) {
      return res
        .status(403)
        .json({ error: "Not the turf owner", code: "FORBIDDEN" });
    }

    // Decode base64 -> buffer with size guards.
    let buffer;
    try {
      buffer = Buffer.from(imageData, "base64");
    } catch (_) {
      return res
        .status(400)
        .json({ error: "Invalid base64 image data", code: "INVALID_DATA" });
    }
    if (!buffer || buffer.length === 0) {
      return res
        .status(400)
        .json({ error: "Empty image data", code: "EMPTY_DATA" });
    }
    // S5: hard cap on decoded buffer
    if (buffer.length > MAX_DECODED_BYTES) {
      return res
        .status(413)
        .json({ error: "Image exceeds 5 MB", code: "TOO_LARGE" });
    }

    // S4: real-type detection. Anything that isn't a real JPEG/PNG/WebP is rejected.
    const detected = detectImageType(buffer);
    if (!detected) {
      return res.status(400).json({
        error: "Unsupported image type (only JPEG, PNG, WebP allowed)",
        code: "INVALID_IMAGE",
      });
    }

    // S3: server-generated filename. Caller's filename is ignored.
    const generatedName = `${crypto.randomUUID()}.${detected.ext}`;
    const path = `turfs/${turfId}/images/${generatedName}`;

    // S2: upsert disabled — never silently overwrite an existing object.
    const { error: upErr } = await supabase.storage
      .from(STORAGE_BUCKET)
      .upload(path, buffer, {
        contentType: detected.contentType,
        upsert: false,
      });

    if (upErr) {
      // S7: log full error server-side, return generic message + code.
      console.error("Supabase upload error:", upErr);
      return res
        .status(500)
        .json({ error: "Upload failed", code: "UPLOAD_STORAGE" });
    }

    const { data: urlData } = supabase.storage
      .from(STORAGE_BUCKET)
      .getPublicUrl(path);

    return res.json({
      success: true,
      url: urlData.publicUrl,
      path,
      fileName: generatedName,
    });
  } catch (e) {
    // S7: never leak raw error text
    console.error("Upload handler error:", e);
    return res
      .status(500)
      .json({ error: "Upload failed", code: "UPLOAD_INTERNAL" });
  }
}
