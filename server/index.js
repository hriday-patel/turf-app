import express from "express";
import cors from "cors";
import dotenv from "dotenv";
import { createClient } from "@supabase/supabase-js";

dotenv.config();

const app = express();
app.use(cors());
app.use(express.json());

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !supabaseServiceKey) {
  console.error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseServiceKey, {
  auth: {
    persistSession: false,
  },
});

app.get("/health", (_req, res) => {
  res.json({ ok: true });
});

app.post("/slots/reserve", async (req, res) => {
  const { slotId, userId, reservationMinutes } = req.body;
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
});

app.post("/slots/release", async (req, res) => {
  const { slotId } = req.body;
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
});

app.post("/slots/book", async (req, res) => {
  const { slotId } = req.body;
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
});

app.post("/bookings/create", async (req, res) => {
  const { slotId, booking } = req.body;
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
});

app.post("/bookings/cancel", async (req, res) => {
  const { bookingId, slotId, cancelledBy, reason } = req.body;
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
});

const port = process.env.PORT || 8080;
app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});
