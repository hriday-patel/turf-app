import crypto from "node:crypto";
import { applyCors } from "../_utils/cors.js";

// W9: Validate required env vars at module load — a misconfigured deploy must
// fail loudly, not silently break Meta's verification or HMAC checks.
const VERIFY_TOKEN = (() => {
  const raw = String(process.env.WHATSAPP_WEBHOOK_VERIFY_TOKEN || "").trim();
  if (!raw) {
    throw new Error("WHATSAPP_WEBHOOK_VERIFY_TOKEN env var is required.");
  }
  return raw;
})();

const APP_SECRET = (() => {
  const raw = String(process.env.WHATSAPP_APP_SECRET || "").trim();
  if (!raw) {
    throw new Error("WHATSAPP_APP_SECRET env var is required.");
  }
  return raw;
})();

// W6: HMAC verification needs the raw request body. Disable Vercel's
// automatic JSON body parser so we can read and hash the bytes Meta sent.
export const config = {
  api: {
    bodyParser: false,
  },
};

function readRawBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let total = 0;
    const limit = 1024 * 1024; // 1 MB; Meta payloads are tiny.
    req.on("data", (chunk) => {
      total += chunk.length;
      if (total > limit) {
        reject(new Error("Payload too large"));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => resolve(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}

// W8: timing-safe compare for both the verify token and the HMAC signature.
function timingSafeEqualStr(a, b) {
  const aBuf = Buffer.from(String(a), "utf8");
  const bBuf = Buffer.from(String(b), "utf8");
  if (aBuf.length !== bBuf.length) return false;
  return crypto.timingSafeEqual(aBuf, bBuf);
}

function verifySignature(rawBody, headerSig) {
  if (!headerSig || typeof headerSig !== "string") return false;
  if (!headerSig.startsWith("sha256=")) return false;
  const provided = headerSig.slice("sha256=".length);
  const expected = crypto
    .createHmac("sha256", APP_SECRET)
    .update(rawBody)
    .digest("hex");
  // Both are hex strings of equal length when valid; timing-safe compare.
  if (provided.length !== expected.length) return false;
  try {
    return crypto.timingSafeEqual(
      Buffer.from(provided, "hex"),
      Buffer.from(expected, "hex"),
    );
  } catch (_) {
    return false;
  }
}

// W7: Build a redacted, log-safe summary of an inbound webhook payload.
// Never write phone numbers or message text to logs.
function summarizePayload(parsed) {
  try {
    const entries = Array.isArray(parsed?.entry) ? parsed.entry : [];
    const summary = entries.map((entry) => {
      const changes = Array.isArray(entry?.changes) ? entry.changes : [];
      return {
        changes: changes.map((c) => {
          const value = c?.value || {};
          const messages = Array.isArray(value.messages) ? value.messages : [];
          const statuses = Array.isArray(value.statuses) ? value.statuses : [];
          return {
            field: c?.field,
            messageCount: messages.length,
            messageTypes: messages.map((m) => m?.type).filter(Boolean),
            statusCount: statuses.length,
            statusTypes: statuses.map((s) => s?.status).filter(Boolean),
          };
        }),
      };
    });
    return { object: parsed?.object, entries: summary };
  } catch (_) {
    return { object: null, entries: [] };
  }
}

export default async function handler(req, res) {
  if (applyCors(req, res)) return;

  if (req.method === "GET") {
    const mode = req.query["hub.mode"];
    const challenge = req.query["hub.challenge"];
    const verifyToken = req.query["hub.verify_token"];

    if (
      mode === "subscribe" &&
      typeof verifyToken === "string" &&
      timingSafeEqualStr(verifyToken, VERIFY_TOKEN)
    ) {
      return res.status(200).send(challenge);
    }

    // W9: never echo env-var names; generic forbidden response.
    return res.status(403).send("Forbidden");
  }

  if (req.method === "POST") {
    let rawBody;
    try {
      rawBody = await readRawBody(req);
    } catch (e) {
      console.error("Webhook body read failed:", e?.message || e);
      return res.status(413).json({ error: "Payload too large" });
    }

    // W6: verify Meta's HMAC signature on every POST. Reject forgeries.
    const sig = req.headers["x-hub-signature-256"];
    if (!verifySignature(rawBody, sig)) {
      console.warn("Webhook signature verification failed.");
      return res.status(403).json({ error: "Invalid signature" });
    }

    // W7: parse for our own logging/processing, but log only redacted summary.
    let parsed = null;
    try {
      parsed = JSON.parse(rawBody.toString("utf8") || "{}");
    } catch (_) {
      parsed = null;
    }

    console.log("WhatsApp webhook event:", summarizePayload(parsed));

    return res.status(200).json({ received: true });
  }

  return res.status(405).json({ error: "Method not allowed" });
}
