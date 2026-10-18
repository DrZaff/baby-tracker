// Sends a push notification to every caregiver (except the person who made the
// change) when an entry or photo is added or edited.
const { onDocumentWritten, onDocumentCreated } = require("firebase-functions/v2/firestore");
const { logger } = require("firebase-functions");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();
const db = getFirestore();

async function notifyCaregivers(babyId, actorUid, body) {
  const babySnap = await db.doc(`babies/${babyId}`).get();
  if (!babySnap.exists) return;
  const baby = babySnap.data();
  const emails = baby.memberEmails || [];

  // Firestore "in" queries take at most 30 values.
  const users = [];
  for (let i = 0; i < emails.length; i += 30) {
    const snap = await db.collection("users").where("email", "in", emails.slice(i, i + 30)).get();
    users.push(...snap.docs);
  }

  const tokens = [];
  const tokenOwner = {};
  for (const user of users) {
    if (user.id === actorUid) continue;
    for (const token of user.get("fcmTokens") || []) {
      tokens.push(token);
      tokenOwner[token] = user.id;
    }
  }
  if (tokens.length === 0) return;

  const response = await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title: baby.name || "Little Log", body },
    apns: { payload: { aps: { sound: "default" } } },
    data: { babyId },
  });

  // Forget tokens for uninstalled apps or signed-out devices.
  const stale = [];
  response.responses.forEach((r, i) => {
    const code = r.error && r.error.code;
    if (code === "messaging/registration-token-not-registered" || code === "messaging/invalid-registration-token") {
      stale.push(tokens[i]);
    }
  });
  await Promise.all(
    stale.map((token) =>
      db.doc(`users/${tokenOwner[token]}`).update({ fcmTokens: FieldValue.arrayRemove(token) })
    )
  );
  logger.info(`Notified ${tokens.length - stale.length} device(s) for baby ${babyId}`);
}

exports.onEntryWritten = onDocumentWritten("babies/{babyId}/entries/{entryId}", async (event) => {
  const after = event.data && event.data.after;
  if (!after || !after.exists) return; // Deleted
  const entry = after.data();
  const isNew = !event.data.before.exists;
  const actorUid = isNew ? entry.createdByUid : entry.updatedByUid || entry.createdByUid;
  const actorName = isNew ? entry.createdByName : entry.updatedByName || entry.createdByName;
  const what = entry.summary || entry.kind;
  const body = isNew ? `${actorName} logged ${what}` : `${actorName} edited ${what}`;
  await notifyCaregivers(event.params.babyId, actorUid, body);
});

exports.onPhotoCreated = onDocumentCreated("babies/{babyId}/photos/{photoId}", async (event) => {
  const photo = event.data && event.data.data();
  if (!photo) return;
  await notifyCaregivers(event.params.babyId, photo.createdByUid, `${photo.createdByName} shared a new photo`);
});
