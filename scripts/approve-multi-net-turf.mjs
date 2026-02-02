// Run this script with: node scripts/approve-multi-net-turf.mjs
// Approves turfs with 2 or more nets for testing

import { createClient } from "@supabase/supabase-js";

const supabaseUrl =
  process.env.SUPABASE_URL || "https://yfanvvndqcixwdlhedqo.supabase.co";
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseServiceKey) {
  console.error(
    "❌ Error: SUPABASE_SERVICE_ROLE_KEY environment variable is required",
  );
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseServiceKey, {
  auth: { persistSession: false },
});

async function approveMultiNetTurf(ownerEmail, minNets = 2) {
  console.log(`\n🔍 Looking for owner with email: ${ownerEmail}`);
  console.log(`🎯 Targeting turfs with ${minNets}+ nets`);

  // Find the owner by email
  const { data: owner, error: ownerError } = await supabase
    .from("owners")
    .select("id, name, email, phone")
    .eq("email", ownerEmail)
    .single();

  if (ownerError || !owner) {
    console.error("❌ Owner not found:", ownerError);
    return;
  }

  console.log(`✅ Found owner: ${owner.name} (Phone: ${owner.phone})`);

  // Find turfs for this owner
  const { data: turfs, error: turfsError } = await supabase
    .from("turfs")
    .select("id, turf_name, verification_status, number_of_nets")
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
    const nets = t.number_of_nets || 1;
    const marker = nets >= minNets ? "✅" : "  ";
    console.log(
      `${marker} ${i + 1}. ${t.turf_name} - Status: ${t.verification_status} - Nets: ${nets}`,
    );
  });

  // Find turfs with minNets or more that are pending
  const turfsWithMultiNets = turfs.filter(
    (t) => (t.number_of_nets || 1) >= minNets,
  );

  if (turfsWithMultiNets.length === 0) {
    console.log(`\n❌ No turf found with ${minNets}+ nets`);
    console.log("\n📝 Would you like to update a turf to have more nets? Run:");
    console.log(
      "   node scripts/update-turf-nets.mjs <turf_id> <number_of_nets>",
    );
    return;
  }

  const turfToApprove =
    turfsWithMultiNets.find((t) => t.verification_status === "PENDING") ||
    turfsWithMultiNets[0];

  console.log(
    `\n🔄 Approving turf: ${turfToApprove.turf_name} (${turfToApprove.number_of_nets || 1} nets)`,
  );

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
  console.log(`   Nets: ${updatedTurf.number_of_nets || 1}`);
  console.log(`   Status: ${updatedTurf.verification_status}`);
}

// Run the script
const email = process.argv[2] || "patelhriday23@gmail.com";
const minNets = parseInt(process.argv[3]) || 2;
approveMultiNetTurf(email, minNets).catch(console.error);
