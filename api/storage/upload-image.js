import { supabase } from "../_utils/supabase.js";
import { applyCors } from "../_utils/cors.js";

export const config = {
  api: {
    bodyParser: {
      sizeLimit: "10mb",
    },
  },
};

export default async function handler(req, res) {
  if (applyCors(req, res)) return;

  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  try {
    const { imageData, turfId, fileName, contentType } = req.body || {};

    if (!imageData || !turfId || !fileName) {
      return res.status(400).json({
        error: "Missing required fields: imageData, turfId, fileName",
      });
    }

    // Convert base64 to buffer
    const buffer = Buffer.from(imageData, "base64");

    // Generate path
    const path = `turfs/${turfId}/images/${fileName}`;

    // Upload to Supabase Storage
    const { data, error } = await supabase.storage
      .from("turf-images")
      .upload(path, buffer, {
        contentType: contentType || "image/jpeg",
        upsert: true,
      });

    if (error) {
      console.error("Supabase upload error:", error);
      return res.status(500).json({ error: error.message });
    }

    // Get public URL
    const { data: urlData } = supabase.storage
      .from("turf-images")
      .getPublicUrl(path);

    return res.json({
      success: true,
      url: urlData.publicUrl,
      path: path,
    });
  } catch (e) {
    console.error("Upload error:", e);
    return res.status(500).json({ error: e.message || "Upload failed" });
  }
}
