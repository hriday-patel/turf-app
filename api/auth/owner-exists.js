const { supabase } = require("../_utils/supabase");
const { applyCors } = require("../_utils/cors");

module.exports = async (req, res) => {
  if (applyCors(req, res)) return;
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const { email, phone } = req.body || {};
  if (!email && !phone) {
    return res.status(400).json({ error: "Email or phone is required." });
  }

  if (email) {
    const { data, error } = await supabase
      .from("owners")
      .select("id")
      .eq("email", email)
      .maybeSingle();

    if (error) {
      return res.status(500).json({ error: error.message });
    }

    if (data) return res.json({ exists: true });
  }

  if (phone) {
    const { data, error } = await supabase
      .from("owners")
      .select("id")
      .eq("phone", phone)
      .maybeSingle();

    if (error) {
      return res.status(500).json({ error: error.message });
    }

    if (data) return res.json({ exists: true });
  }

  return res.json({ exists: false });
};
