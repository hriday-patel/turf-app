const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();

function normalizePhone(phone) {
  if (typeof phone !== "string") return "";
  return phone.trim();
}

exports.checkOwnerPhoneExists = functions.https.onCall(
  async (data, context) => {
    const phone = normalizePhone(data.phone);
    if (!phone || !phone.startsWith("+")) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Invalid phone number.",
      );
    }

    const doc = await db.collection("owner_phone_index").doc(phone).get();
    return { exists: doc.exists };
  },
);

exports.getOwnerUidByPhone = functions.https.onCall(async (data, context) => {
  const phone = normalizePhone(data.phone);
  if (!phone || !phone.startsWith("+")) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Invalid phone number.",
    );
  }

  const doc = await db.collection("owner_phone_index").doc(phone).get();
  if (!doc.exists) {
    return { ownerUid: null };
  }

  const ownerUid = doc.data().ownerId;
  return { ownerUid };
});

exports.linkPhoneToOwnerAndIssueToken = functions.https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Authentication required.",
      );
    }

    const phone = normalizePhone(data.phone);
    const phoneAuthUid = data.phoneAuthUid;

    if (!phone || !phone.startsWith("+") || typeof phoneAuthUid !== "string") {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Invalid request.",
      );
    }

    if (context.auth.uid !== phoneAuthUid) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Invalid auth session.",
      );
    }

    const verifiedPhone = context.auth.token.phone_number;
    if (verifiedPhone !== phone) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Phone verification failed.",
      );
    }

    const indexDoc = await db.collection("owner_phone_index").doc(phone).get();
    if (!indexDoc.exists) {
      throw new functions.https.HttpsError(
        "not-found",
        "Owner not found for phone.",
      );
    }

    const ownerUid = indexDoc.data().ownerId;
    if (!ownerUid) {
      throw new functions.https.HttpsError(
        "not-found",
        "Owner not found for phone.",
      );
    }

    await admin.auth().updateUser(ownerUid, { phoneNumber: phone });

    if (ownerUid !== phoneAuthUid) {
      await admin.auth().deleteUser(phoneAuthUid);
    }

    const customToken = await admin.auth().createCustomToken(ownerUid);
    return { customToken };
  },
);
