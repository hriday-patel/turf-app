const { supabase } = require("../_utils/supabase");
const { applyCors } = require("../_utils/cors");

module.exports = async (req, res) => {
  if (applyCors(req, res)) return;
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const { slotId, booking } = req.body || {};
  if (!slotId || !booking) {
    return res.status(400).json({ error: "Invalid request." });
  }

  const { data, error } = await supabase.rpc("create_booking_atomic", {
    slot_id: slotId,
    booking_data: booking,
  });

  if (error) {
    return res.status(500).json({ error: error.message });
  }

  return res.json({ bookingId: data });
};
