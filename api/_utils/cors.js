function parseAllowedOrigins() {
  const raw = String(process.env.ALLOWED_ORIGINS || "").trim();
  if (!raw) return [];
  return raw
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
}

function isAllowedOrigin(origin, allowList) {
  if (!origin) return false;
  if (allowList.includes(origin)) return true;
  // Dev convenience: any localhost / 127.0.0.1 origin (any port, http/https).
  try {
    const u = new URL(origin);
    if (u.hostname === "localhost" || u.hostname === "127.0.0.1") {
      return true;
    }
  } catch (_) {
    return false;
  }
  return false;
}

export function applyCors(req, res) {
  const origin = req.headers.origin;
  const allowList = parseAllowedOrigins();

  if (origin && isAllowedOrigin(origin, allowList)) {
    res.setHeader("Access-Control-Allow-Origin", origin);
    res.setHeader("Vary", "Origin");
  }
  // For requests without an Origin header (server-to-server, e.g. Meta
  // webhook callbacks) we simply don't set the header. Browsers will block
  // disallowed origins; non-browser callers are unaffected.

  res.setHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");

  if (req.method === "OPTIONS") {
    res.status(204).end();
    return true;
  }

  return false;
}
