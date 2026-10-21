// Sends a push notification to every caregiver (except the person who made the
// change) when an entry or photo is added or edited, and feed reminders when a
// baby hasn't been fed for the time set in the app.
const { onDocumentWritten, onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
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
    // content-available lets the app refresh its home screen widget.
    apns: { payload: { aps: { sound: "default", contentAvailable: true } } },
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
  const before = isNew ? null : event.data.before.data();
  let body = isNew ? `${actorName} logged ${what}` : `${actorName} edited ${what}`;
  if (entry.kind === "sleep" && before && !before.sleepEnd && entry.sleepEnd) {
    const minutes = Math.round((entry.sleepEnd.toMillis() - entry.timestamp.toMillis()) / 60000);
    const slept = minutes >= 60 ? `${Math.floor(minutes / 60)}h ${minutes % 60}m` : `${minutes}m`;
    body = `${actorName} logged a wake-up after ${slept} of sleep`;
  }
  await notifyCaregivers(event.params.babyId, actorUid, body);
});

exports.onAppointmentWritten = onDocumentWritten("babies/{babyId}/appointments/{appointmentId}", async (event) => {
  const after = event.data && event.data.after;
  if (!after || !after.exists) return; // Deleted
  const appointment = after.data();
  const isNew = !event.data.before.exists;
  const actorUid = isNew ? appointment.createdByUid : appointment.updatedByUid || appointment.createdByUid;
  const actorName = isNew ? appointment.createdByName : appointment.updatedByName || appointment.createdByName;
  const what = appointment.summary || "an appointment";
  const body = isNew ? `🦉 ${actorName} added ${what}` : `🦉 ${actorName} updated ${what}`;
  await notifyCaregivers(event.params.babyId, actorUid, body);
});

exports.onPhotoCreated = onDocumentCreated("babies/{babyId}/photos/{photoId}", async (event) => {
  const photo = event.data && event.data.data();
  if (!photo) return;
  await notifyCaregivers(event.params.babyId, photo.createdByUid, `${photo.createdByName} shared a new photo`);
});

function isFeeding(entry) {
  if (entry.kind !== "feed") return false;
  const breast = (entry.breastLeftSeconds || 0) + (entry.breastRightSeconds || 0);
  return breast > 0 || (entry.bottleML || 0) > 0;
}

// Every 10 minutes, remind caregivers of babies whose last feed is older than
// their feed reminder setting. Each feed gets at most one reminder.
exports.feedReminders = onSchedule("every 10 minutes", async () => {
  const babies = await db.collection("babies").where("feedReminderHours", ">", 0).get();
  const now = Date.now();
  for (const babyDoc of babies.docs) {
    const baby = babyDoc.data();
    const recent = await babyDoc.ref.collection("entries").orderBy("timestamp", "desc").limit(40).get();
    const lastFeed = recent.docs.find((d) => isFeeding(d.data()));
    if (!lastFeed) continue;
    const fedAt = lastFeed.get("timestamp").toMillis();
    const hours = baby.feedReminderHours;
    // Skip feeds older than a day so an unused log doesn't keep pinging.
    if (now - fedAt < hours * 3600 * 1000 || now - fedAt > 24 * 3600 * 1000) continue;
    if (baby.lastFeedReminderFor === lastFeed.id) continue;
    await babyDoc.ref.update({ lastFeedReminderFor: lastFeed.id });
    await notifyCaregivers(babyDoc.id, null, `⏰ It's been ${hours} hours since ${baby.name || "the baby"}'s last feed`);
  }
});
