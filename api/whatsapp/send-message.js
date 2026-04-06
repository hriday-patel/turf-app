import { applyCors } from "../_utils/cors.js";

const DEFAULT_GRAPH_API_VERSION = "v23.0";

function normalizePhoneNumber(phone) {
  const digits = String(phone || "").replace(/\D/g, "");

  if (digits.length < 10) {
    return null;
  }

  // WhatsApp Cloud API expects E.164-style digits without a leading plus.
  if (digits.length === 10) {
    return `91${digits}`;
  }

  return digits;
}

function buildWhatsAppPayload(body, normalizedTo) {
  const template = body?.template;

  if (template?.name) {
    return {
      messaging_product: "whatsapp",
      to: normalizedTo,
      type: "template",
      template: {
        name: template.name,
        language: {
          code: template.languageCode || "en_US",
        },
        ...(Array.isArray(template.components) && template.components.length > 0
          ? { components: template.components }
          : {}),
      },
    };
  }

  const message = String(body?.message || "").trim();
  if (!message) {
    return null;
  }

  return {
    messaging_product: "whatsapp",
    recipient_type: "individual",
    to: normalizedTo,
    type: "text",
    text: {
      preview_url: false,
      body: message,
    },
  };
}

export default async function handler(req, res) {
  if (applyCors(req, res)) return;

  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const accessToken = process.env.WHATSAPP_API_KEY;
  const phoneNumberId = process.env.WHATSAPP_PHONE_ID;
  const graphApiVersion =
    process.env.WHATSAPP_GRAPH_API_VERSION || DEFAULT_GRAPH_API_VERSION;

  if (!accessToken || !phoneNumberId) {
    return res.status(500).json({
      error: "Missing WHATSAPP_API_KEY or WHATSAPP_PHONE_ID",
    });
  }

  const normalizedTo = normalizePhoneNumber(req.body?.to);
  if (!normalizedTo) {
    return res.status(400).json({ error: "Invalid recipient phone number" });
  }

  const payload = buildWhatsAppPayload(req.body, normalizedTo);
  if (!payload) {
    return res.status(400).json({
      error:
        "Missing message payload. Provide `message` for text or `template.name` for templates.",
    });
  }

  try {
    const graphResponse = await fetch(
      `https://graph.facebook.com/${graphApiVersion}/${phoneNumberId}/messages`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
      },
    );

    const rawBody = await graphResponse.text();
    let responseBody = {};

    if (rawBody) {
      try {
        responseBody = JSON.parse(rawBody);
      } catch (_) {
        responseBody = { rawBody };
      }
    }

    if (!graphResponse.ok) {
      return res.status(graphResponse.status).json({
        error:
          responseBody?.error?.message ||
          "Failed to send message via WhatsApp Cloud API",
        details: responseBody,
      });
    }

    return res.status(200).json({
      success: true,
      messageId: responseBody?.messages?.[0]?.id || null,
      contacts: responseBody?.contacts || [],
    });
  } catch (error) {
    console.error("WhatsApp send-message error:", error);
    return res.status(500).json({
      error: "Unexpected error while sending WhatsApp message",
      details: error?.message || String(error),
    });
  }
}
