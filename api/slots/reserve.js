import { supabase } from "../_utils/supabase.js";
import { applyCors } from "../_utils/cors.js";

export default async function handler(req, res) {
  if (applyCors(req, res)) return;
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const { slotId, userId, reservationMinutes } = req.body || {};
  if (!slotId || !userId || !reservationMinutes) {
    return res.status(400).json({ error: "Invalid request." });
  }

  const { data, error } = await supabase.rpc("reserve_slot", {
    slot_id: slotId,
    reserved_by: userId,
    reservation_minutes: reservationMinutes,
  });

  if (error) {
    return res.status(500).json({ error: error.message });
  }

  return res.json({ success: data === true });
}
