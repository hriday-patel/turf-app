// Run this script with: node scripts/approve-turf.mjs
// Make sure to set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY environment variables

import { createClient } from "@supabase/supabase-js";

const supabaseUrl =
  process.env.SUPABASE_URL || "https://yfanvvndqcixwdlhedqo.supabase.co";
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseServiceKey) {
  console.error(
    "❌ Error: SUPABASE_SERVICE_ROLE_KEY environment variable is required",
  );
  console.log(
    "Run with: SUPABASE_SERVICE_ROLE_KEY=your_key node scripts/approve-turf.mjs",
  );
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseServiceKey, {
  auth: { persistSession: false },
});

async function approveTurf(ownerEmail) {
  console.log(`\n🔍 Looking for owner with email: ${ownerEmail}`);

  // Find the owner by email
  const { data: owner, error: ownerError } = await supabase
    .from("owners")
    .select("id, name, email")
    .eq("email", ownerEmail)
    .single();

  if (ownerError || !owner) {
    console.error("❌ Owner not found:", ownerError);
    return;
  }

  console.log(`✅ Found owner: ${owner.name} (${owner.id})`);

  // Find turfs for this owner
  const { data: turfs, error: turfsError } = await supabase
    .from("turfs")
    .select("id, turf_name, verification_status")
    .eq("owner_id", owner.id);

  if (turfsError) {
    console.error("❌ Failed to fetch turfs:", turfsError);
    return;
  }

  if (!turfs || turfs.length === 0) {
    console.log("❌ No turfs found for this owner");
    return;
  }

  console.log(`\n📋 Found ${turfs.length} turf(s):`);
  turfs.forEach((t, i) => {
    console.log(
      `   ${i + 1}. ${t.turf_name} - Status: ${t.verification_status}`,
    );
  });

  // Find pending turf or first turf
  const turfToApprove =
    turfs.find((t) => t.verification_status === "PENDING") || turfs[0];

  console.log(`\n🔄 Approving turf: ${turfToApprove.turf_name}`);

  // Update the turf
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
    console.error("❌ Failed to approve turf:", updateError);
    return;
  }

  console.log(`\n✅ SUCCESS! Turf "${updatedTurf.turf_name}" is now APPROVED!`);
  console.log(`   ID: ${updatedTurf.id}`);
  console.log(`   Status: ${updatedTurf.verification_status}`);
}

// Run the script
const email = process.argv[2] || "patelhriday23@gmail.com";
approveTurf(email).catch(console.error);
