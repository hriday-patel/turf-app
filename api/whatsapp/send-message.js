import { applyCors } from "../_utils/cors.js";
import { supabase } from "../_utils/supabase.js";

const DEFAULT_GRAPH_API_VERSION = "v23.0";

// W4: WhatsApp Cloud API hard limit on text body length.
const MAX_MESSAGE_LENGTH = 4096;

// W5: Server-side template allowlist. Only templates explicitly listed in the
// WHATSAPP_ALLOWED_TEMPLATES env var (comma-separated) may be sent. This
// prevents callers from invoking arbitrary approved templates with
// attacker-chosen variables (e.g. an OTP template added later).
const TEMPLATE_ALLOWLIST = (() => {
  const raw = String(process.env.WHATSAPP_ALLOWED_TEMPLATES || "").trim();
  if (!raw) return new Set();
  return new Set(
    raw
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean),
  );
})();

// W2: Per-user + per-IP rate limit (in-memory; per serverless instance).
const RATE_LIMIT_USER_MAX = 30;
const RATE_LIMIT_IP_MAX = 60;
const RATE_LIMIT_WINDOW_MS = 10 * 60 * 1000;
const rateLimitMap = new Map();

function checkRateLimit(key, max) {
  const now = Date.now();
  const entry = rateLimitMap.get(key);
  if (!entry || now - entry.windowStart > RATE_LIMIT_WINDOW_MS) {
    rateLimitMap.set(key, { count: 1, windowStart: now });
    return true;
  }
  entry.count += 1;
  return entry.count <= max;
}

function getClientIp(req) {
  const fwd = req.headers["x-forwarded-for"];
  if (typeof fwd === "string" && fwd.length) {
    return fwd.split(",")[0].trim();
  }
  return req.socket?.remoteAddress || "unknown";
}

function normalizePhoneNumber(phone) {
  const digits = String(phone || "").replace(/\D/g, "");

  if (digits.length < 10) {
    return null;
  }

  // WhatsApp Cloud API expects E.164-style digits without a leading plus.
  if (digits.length === 10) {
    return `91${digits}`;
  }

  return digits;
}

function buildWhatsAppPayload(body, normalizedTo) {
  const template = body?.template;

  if (template?.name) {
    const name = String(template.name).trim();
    if (!TEMPLATE_ALLOWLIST.has(name)) {
      return { error: "TEMPLATE_NOT_ALLOWED" };
    }
    return {
      payload: {
        messaging_product: "whatsapp",
        to: normalizedTo,
        type: "template",
        template: {
          name,
          language: {
            code: template.languageCode || "en_US",
          },
          ...(Array.isArray(template.components) &&
          template.components.length > 0
            ? { components: template.components }
            : {}),
        },
      },
    };
  }

  const message = String(body?.message || "").trim();
  if (!message) {
    return { error: "MISSING_FIELDS" };
  }
  if (message.length > MAX_MESSAGE_LENGTH) {
    return { error: "MESSAGE_TOO_LONG" };
  }

  return {
    payload: {
      messaging_product: "whatsapp",
      recipient_type: "individual",
      to: normalizedTo,
      type: "text",
      text: {
        preview_url: false,
        body: message,
      },
    },
  };
}

// W4: Cap incoming JSON body so a caller cannot waste bandwidth/CPU.
export const config = {
  api: {
    bodyParser: {
      sizeLimit: "32kb",
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

  // W2: per-IP rate limit first (cheap, runs before auth lookup).
  const ip = getClientIp(req);
  if (!checkRateLimit(`ip:${ip}`, RATE_LIMIT_IP_MAX)) {
    return res
      .status(429)
      .json({ error: "Too many requests", code: "RATE_LIMITED" });
  }

  // W1: require a valid Supabase Bearer token.
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
    console.error("WhatsApp auth lookup failed:", e);
    return res
      .status(401)
      .json({ error: "Invalid token", code: "AUTH_INVALID" });
  }

  // W2: per-user rate limit after we know who the caller is.
  if (!checkRateLimit(`user:${userId}`, RATE_LIMIT_USER_MAX)) {
    return res
      .status(429)
      .json({ error: "Too many requests", code: "RATE_LIMITED" });
  }

  const accessToken = process.env.WHATSAPP_API_KEY;
  const phoneNumberId = process.env.WHATSAPP_PHONE_ID;
  const graphApiVersion =
    process.env.WHATSAPP_GRAPH_API_VERSION || DEFAULT_GRAPH_API_VERSION;

  if (!accessToken || !phoneNumberId) {
    console.error("WhatsApp env vars missing (WHATSAPP_API_KEY/PHONE_ID).");
    return res
      .status(500)
      .json({ error: "Service unavailable", code: "WHATSAPP_CONFIG" });
  }

  const normalizedTo = normalizePhoneNumber(req.body?.to);
  if (!normalizedTo) {
    return res
      .status(400)
      .json({ error: "Invalid recipient", code: "INVALID_PHONE" });
  }

  const built = buildWhatsAppPayload(req.body, normalizedTo);
  if (built.error === "TEMPLATE_NOT_ALLOWED") {
    return res
      .status(400)
      .json({ error: "Template not allowed", code: "TEMPLATE_NOT_ALLOWED" });
  }
  if (built.error === "MESSAGE_TOO_LONG") {
    return res
      .status(400)
      .json({ error: "Message too long", code: "MESSAGE_TOO_LONG" });
  }
  if (built.error === "MISSING_FIELDS" || !built.payload) {
    return res
      .status(400)
      .json({ error: "Missing message payload", code: "MISSING_FIELDS" });
  }

  try {
    const graphResponse = await fetch(
      `https://graph.facebook.com/${graphApiVersion}/${phoneNumberId}/messages`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(built.payload),
      },
    );

    const rawBody = await graphResponse.text();
    let responseBody = {};
    if (rawBody) {
      try {
        responseBody = JSON.parse(rawBody);
      } catch (_) {
        responseBody = { rawBody };
      }
    }

    if (!graphResponse.ok) {
      // W3: log full Meta error server-side; do not echo to client.
      console.error(
        "WhatsApp Cloud API error:",
        graphResponse.status,
        responseBody,
      );
      return res
        .status(502)
        .json({ error: "Send failed", code: "WHATSAPP_SEND" });
    }

    return res.status(200).json({
      success: true,
      messageId: responseBody?.messages?.[0]?.id || null,
    });
  } catch (error) {
    // W3: never leak error details to client.
    console.error("WhatsApp send-message error:", error);
    return res
      .status(500)
      .json({ error: "Send failed", code: "WHATSAPP_SEND" });
  }
}
