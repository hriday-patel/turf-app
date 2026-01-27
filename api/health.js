const { applyCors } = require("./_utils/cors");

module.exports = async (req, res) => {
  if (applyCors(req, res)) return;
  res.status(200).json({ ok: true, time: new Date().toISOString() });
};
