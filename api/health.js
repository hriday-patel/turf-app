import { applyCors } from "./_utils/cors.js";

export default async function handler(req, res) {
  if (applyCors(req, res)) return;
  res.status(200).json({ ok: true, time: new Date().toISOString() });
}
