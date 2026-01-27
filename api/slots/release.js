import { supabase } from "../_utils/supabase.js";
import { applyCors } from "../_utils/cors.js";

export default async function handler(req, res) {
  if (applyCors(req, res)) return;
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const { slotId } = req.body || {};
  if (!slotId) {
    return res.status(400).json({ error: "Invalid request." });
  }

  const { error } = await supabase.rpc("release_slot", {
    slot_id: slotId,
  });

  if (error) {
    return res.status(500).json({ error: error.message });
  }

  return res.json({ success: true });
}
