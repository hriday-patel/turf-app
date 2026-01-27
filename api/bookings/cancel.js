const { supabase } = require("../_utils/supabase");
const { applyCors } = require("../_utils/cors");

module.exports = async (req, res) => {
  if (applyCors(req, res)) return;
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const { bookingId, slotId, cancelledBy, reason } = req.body || {};
  if (!bookingId || !slotId || !cancelledBy) {
    return res.status(400).json({ error: "Invalid request." });
  }

  const { data, error } = await supabase.rpc("cancel_booking", {
    booking_id: bookingId,
    slot_id: slotId,
    cancelled_by: cancelledBy,
    cancel_reason: reason || null,
  });

  if (error) {
    return res.status(500).json({ error: error.message });
  }

  return res.json({ success: data === true });
};
