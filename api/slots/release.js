const { supabase } = require("../_utils/supabase");
const { applyCors } = require("../_utils/cors");

module.exports = async (req, res) => {
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
};
