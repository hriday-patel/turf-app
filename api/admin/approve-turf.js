import { supabase } from "../_utils/supabase.js";
import { cors } from "../_utils/cors.js";

export default async function handler(req, res) {
  // Handle CORS
  if (cors(req, res)) return;

  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  try {
    const { ownerEmail } = req.body;

    if (!ownerEmail) {
      return res.status(400).json({ error: "ownerEmail is required" });
    }

    // First, find the owner by email
    const { data: owner, error: ownerError } = await supabase
      .from("owners")
      .select("id, business_name")
      .eq("email", ownerEmail)
      .single();

    if (ownerError || !owner) {
      return res
        .status(404)
        .json({ error: "Owner not found", details: ownerError });
    }

    // Find pending turfs for this owner
    const { data: turfs, error: turfsError } = await supabase
      .from("turfs")
      .select("id, turf_name, verification_status")
      .eq("owner_id", owner.id);

    if (turfsError) {
      return res
        .status(500)
        .json({ error: "Failed to fetch turfs", details: turfsError });
    }

    if (!turfs || turfs.length === 0) {
      return res.status(404).json({ error: "No turfs found for this owner" });
    }

    // Find the first pending turf or any turf
    const turfToApprove =
      turfs.find((t) => t.verification_status === "PENDING") || turfs[0];

    // Update the turf to APPROVED
    const { data: updatedTurf, error: updateError } = await supabase
      .from("turfs")
      .update({
        verification_status: "APPROVED",
        updated_at: new Date().toISOString(),
      })
      .eq("id", turfToApprove.id)
      .select()
      .single();

    if (updateError) {
      return res
        .status(500)
        .json({ error: "Failed to approve turf", details: updateError });
    }

    return res.status(200).json({
      success: true,
      message: `Turf "${updatedTurf.turf_name}" has been approved!`,
      turf: {
        id: updatedTurf.id,
        name: updatedTurf.turf_name,
        status: updatedTurf.verification_status,
      },
    });
  } catch (error) {
    console.error("Error approving turf:", error);
    return res
      .status(500)
      .json({ error: "Internal server error", details: error.message });
  }
}
