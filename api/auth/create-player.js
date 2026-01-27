import { supabase } from "../_utils/supabase.js";
import { applyCors } from "../_utils/cors.js";

export default async function handler(req, res) {
  if (applyCors(req, res)) return;
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const { id, name, email, phone } = req.body || {};
  if (!id || !name || !email || !phone) {
    return res.status(400).json({ error: "Invalid request." });
  }

  const { error } = await supabase.from("players").insert({
    id,
    name,
    email,
    phone,
    role: "PLAYER",
    favorite_turfs: [],
  });

  if (error) {
    if (error.code === "23505") {
      return res
        .status(409)
        .json({ error: "Email or phone already registered." });
    }
    return res.status(500).json({ error: error.message });
  }

  return res.json({ ok: true });
}
