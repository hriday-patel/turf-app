import { applyCors } from "../_utils/cors.js";

export default async function handler(req, res) {
  if (applyCors(req, res)) return;

  if (req.method === "GET") {
    const mode = req.query["hub.mode"];
    const challenge = req.query["hub.challenge"];
    const verifyToken = req.query["hub.verify_token"];

    if (!process.env.WHATSAPP_WEBHOOK_VERIFY_TOKEN) {
      return res
        .status(500)
        .send("Missing WHATSAPP_WEBHOOK_VERIFY_TOKEN server configuration");
    }

    if (
      mode === "subscribe" &&
      verifyToken === process.env.WHATSAPP_WEBHOOK_VERIFY_TOKEN
    ) {
      return res.status(200).send(challenge);
    }

    return res.status(403).send("Webhook verification failed");
  }

  if (req.method === "POST") {
    // Keep this lightweight for now; you can persist events to Supabase later.
    console.log("WhatsApp webhook payload:", JSON.stringify(req.body || {}));
    return res.status(200).json({ received: true });
  }

  return res.status(405).json({ error: "Method not allowed" });
}
