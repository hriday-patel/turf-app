# WhatsApp Cloud API Setup (Project-Specific)

This project now sends WhatsApp messages through serverless API handlers:

- `POST /api/whatsapp/send-message`
- `GET|POST /api/whatsapp/webhook`

These endpoints are implemented in:

- `api/whatsapp/send-message.js`
- `api/whatsapp/webhook.js`

## 1) Configure Vercel Environment Variables

In your Vercel project settings, add:

- `WHATSAPP_API_KEY`
  - Permanent system-user token with:
    - `business_management`
    - `whatsapp_business_messaging`
    - `whatsapp_business_management`
- `WHATSAPP_PHONE_ID`
  - The Phone Number ID from WhatsApp API setup in Meta.
- `WHATSAPP_WEBHOOK_VERIFY_TOKEN`
  - Any long random string you choose.
- `WHATSAPP_GRAPH_API_VERSION` (optional)
  - Defaults to `v23.0`.

## 2) Configure Webhook in Meta App Dashboard

In your WhatsApp app's webhook configuration:

- Callback URL: `https://fieldpass-business.vercel.app/api/whatsapp/webhook`
- Verify token: same value as `WHATSAPP_WEBHOOK_VERIFY_TOKEN`
- Subscribe to message-related fields (at minimum `messages`).

## 3) Test Sending a Message via Your API

```bash
curl -X POST 'https://fieldpass-business.vercel.app/api/whatsapp/send-message' \
  -H 'Content-Type: application/json' \
  -d '{
    "to": "919999999999",
    "message": "Hello from TurfBook WhatsApp Cloud API"
  }'
```

Template send payload format:

```bash
curl -X POST 'https://fieldpass-business.vercel.app/api/whatsapp/send-message' \
  -H 'Content-Type: application/json' \
  -d '{
    "to": "919999999999",
    "template": {
      "name": "hello_world",
      "languageCode": "en_US"
    }
  }'
```

## 4) Flutter Runtime Configuration

The Flutter service now calls your server endpoint from `WhatsAppService`.

Optional dart-define:

```bash
--dart-define=API_BASE_URL=https://fieldpass-business.vercel.app/api
```

If not provided, this project defaults to:

- `https://fieldpass-business.vercel.app/api`

## 5) Where Messages Are Triggered

- Manual booking confirmation: `lib/features/owner/screens/manual_booking_screen.dart`
- Slot booking success popup actions: `lib/features/owner/screens/slot_booking_screen.dart`
- Message transport service: `lib/core/services/whatsapp_service.dart`

## Notes

- Keep access tokens server-side only (never in Flutter app defines).
- Non-template messages require a valid customer service window.
- Use templates for first contact or after the 24-hour window.
