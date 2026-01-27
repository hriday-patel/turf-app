const { supabase } = require("../_utils/supabase");

module.exports = async (req, res) => {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const { slotId } = req.body || {};
  if (!slotId) {
    return res.status(400).json({ error: "Invalid request." });
  }

  const { error } = await supabase.rpc("book_slot", {
    slot_id: slotId,
  });

  if (error) {
    return res.status(500).json({ error: error.message });
  }

  return res.json({ success: true });
};
