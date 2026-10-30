// functions/index.js
// Cloud Functions v2 (Node 18/20/22)
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { setGlobalOptions } = require("firebase-functions/v2/options");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const crypto = require("crypto");

admin.initializeApp();
const db = admin.firestore();

// Set your region (must match your Flutter app's NotificationService.kFunctionsRegion)
setGlobalOptions({ region: "us-central1", maxInstances: 10 });

function normSection(section) {
  if (!section) return null;
  return String(section)
    .replace(/\s+/g, "")
    .replace(/[^A-Za-z0-9_-]/g, "")
    .toUpperCase();
}

// v2 Callable: register device, subscribe to topics, store token
exports.registerDevice = onCall(async (request) => {
  const data = request.data || {};
  const userId = data.userId;
  const role = data.role;
  const section = data.section;
  const token = data.token;
  const platform = data.platform || "unknown";

  if (!userId || !role || !token) {
    throw new Error("Missing userId/role/token");
  }

  const topics = new Set();
  topics.add("all");
  topics.add(`user_${userId}`);
  topics.add(`role_${String(role).toLowerCase()}`);
  const sec = normSection(section);
  if (sec) topics.add(`section_${sec}`);

  for (const t of topics) {
    try {
      await admin.messaging().subscribeToTopic(token, t);
    } catch (e) {
      logger.error("subscribe error", { topic: t, error: String(e) });
    }
  }

  try {
    await admin
      .firestore()
      .collection("userTokens")
      .doc(userId)
      .collection("tokens")
      .doc(token)
      .set(
        {
          token,
          role: String(role).toLowerCase(),
          section: sec || null,
          platform,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
  } catch (e) {
    logger.warn("store token failed", { error: String(e) });
  }

  return { ok: true, topics: Array.from(topics) };
});

// v2 Callable: unregister device (unsubscribe from common topics and stored section)
exports.unregisterDevice = onCall(async (request) => {
  const data = request.data || {};
  const userId = data.userId;
  const token = data.token;
  if (!userId || !token) {
    throw new Error("Missing userId/token");
  }

  const common = ["all", `user_${userId}`, "role_student", "role_teacher", "role_admin"];
  for (const t of common) {
    try {
      await admin.messaging().unsubscribeFromTopic(token, t);
    } catch (e) {
      // best effort
    }
  }

  try {
    const docRef = admin.firestore().collection("userTokens").doc(userId).collection("tokens").doc(token);
    const snap = await docRef.get();
    if (snap.exists) {
      const sec = snap.data().section;
      if (sec) {
        try {
          await admin.messaging().unsubscribeFromTopic(token, `section_${sec}`);
        } catch (e) {
          // best effort
        }
      }
      await docRef.delete();
    }
  } catch (e) {
    logger.warn("cleanup token failed", { error: String(e) });
  }

  return { ok: true };
});

// v2 Callable: broadcast push when attendance is marked (to section + admins)
exports.broadcastAttendanceMarked = onCall(async (request) => {
  const data = request.data || {};
  const section = data.section;
  const subjectName = data.subjectName;
  const day = data.day;
  const timeRange = data.timeRange;
  if (!section || !subjectName || !day || !timeRange) {
    throw new Error("Missing fields");
  }
  const sec = normSection(section);
  const title = `Attendance marked: ${subjectName}`;
  const body = `${day} ${timeRange} • ${section}`;

  const msgs = [
    {
      // Students in the section
      topic: `section_${sec}`,
      notification: { title, body },
      data: { type: "attendanceMarked", section: sec, subject: subjectName, day, time: timeRange },
      webpush: { notification: { title, body } },
      android: { notification: { title, body } },
    },
    {
      // Admins
      topic: "role_admin",
      notification: { title: `Section ${section}`, body },
      data: { type: "attendanceMarkedAdmin", section: sec, subject: subjectName, day, time: timeRange },
      webpush: { notification: { title: `Section ${section}`, body } },
      android: { notification: { title: `Section ${section}`, body } },
    },
  ];

  const results = [];
  for (const m of msgs) {
    try {
      const resId = await admin.messaging().send(m);
      results.push({ ok: true, id: resId });
    } catch (e) {
      logger.error("send error", { error: String(e) });
      results.push({ ok: false, error: String(e) });
    }
  }
  return { ok: true, results };
});

// ---------------------------------------------------------------------------
// SHARED HELPERS
// ---------------------------------------------------------------------------

async function getCaller(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "You must be signed in.");
  }
  const snap = await db.collection("users").doc(request.auth.uid).get();
  if (!snap.exists) {
    throw new HttpsError("permission-denied", "No profile found for this account.");
  }
  const user = { id: snap.id, ...snap.data() };
  if (user.isActive === false) {
    throw new HttpsError("permission-denied", "This account has been deactivated.");
  }
  return user;
}

const isAdmin = (u) => u.role === "admin" || u.isAdmin === true;

// ---------------------------------------------------------------------------
// QR ATTENDANCE
// ---------------------------------------------------------------------------
// The teacher's device gets a random per-session secret from the server and
// signs a rotating step counter with it. Students never see the secret, so the
// only way to produce a valid code is to scan the teacher's live screen.

const QR_STEP_MS = 5000; // must match GenerateQRPage._qrStep
const QR_MAX_AGE_STEPS = 3; // a code is accepted for ~15-20s
const QR_SESSION_MAX_MS = 3 * 60 * 60 * 1000;

function signStep(secret, sessionId, step) {
  return crypto
    .createHmac("sha256", secret)
    .update(`${sessionId}:${step}`)
    .digest("hex")
    .substring(0, 32);
}

exports.startAttendanceSession = onCall(async (request) => {
  const caller = await getCaller(request);
  const entryId = request.data && request.data.entryId;
  if (!entryId) throw new HttpsError("invalid-argument", "Missing entryId.");

  const entrySnap = await db.collection("timetable").doc(entryId).get();
  if (!entrySnap.exists) {
    throw new HttpsError("not-found", "Timetable entry not found.");
  }
  const entry = entrySnap.data();
  const teacherIds = entry.teacherIds || [];
  if (!teacherIds.includes(caller.id) && !isAdmin(caller)) {
    throw new HttpsError("permission-denied", "You do not teach this class.");
  }

  const ref = db.collection("attendance_sessions").doc();
  const secret = crypto.randomBytes(32).toString("hex");
  const createdAt = Timestamp.now();

  const batch = db.batch();
  batch.set(ref, {
    teacherId: caller.id,
    subjectId: entry.subjectId,
    section: entry.section,
    slot: `${entry.startTime}-${entry.endTime}`,
    createdAt,
    isActive: true,
  });
  // Clients have no access to this subcollection (see firestore.rules).
  batch.set(ref.collection("private").doc("key"), { secret });
  await batch.commit();

  return { sessionId: ref.id, secret, createdAtMs: createdAt.toMillis() };
});

exports.markAttendance = onCall(async (request) => {
  const caller = await getCaller(request);
  if (caller.role !== "student") {
    throw new HttpsError("permission-denied", "Only students can mark attendance.");
  }

  const { sId, n, sig } = request.data || {};
  if (typeof sId !== "string" || !Number.isInteger(n) || typeof sig !== "string") {
    throw new HttpsError("invalid-argument", "This is not a valid attendance QR code.");
  }

  const sessionRef = db.collection("attendance_sessions").doc(sId);
  const [sessionSnap, keySnap] = await Promise.all([
    sessionRef.get(),
    sessionRef.collection("private").doc("key").get(),
  ]);
  if (!sessionSnap.exists || !keySnap.exists) {
    throw new HttpsError("not-found", "Attendance session not found.");
  }
  const session = sessionSnap.data();
  const elapsed = Date.now() - session.createdAt.toMillis();

  if (!session.isActive || elapsed > QR_SESSION_MAX_MS) {
    throw new HttpsError("failed-precondition", "This attendance session has ended.");
  }
  if (session.section !== caller.section) {
    throw new HttpsError("permission-denied", "This class is not for your section.");
  }

  const expected = signStep(keySnap.data().secret, sId, n);
  const sigOk = sig.length === expected.length &&
    crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected));
  if (!sigOk) {
    throw new HttpsError("permission-denied", "This is not a valid attendance QR code.");
  }

  const serverStep = Math.floor(elapsed / QR_STEP_MS);
  if (n > serverStep + 1 || n < serverStep - QR_MAX_AGE_STEPS) {
    throw new HttpsError(
      "deadline-exceeded",
      "QR code expired. Please scan the live code directly from the teacher's screen.",
    );
  }

  const now = Timestamp.now();
  try {
    await db.collection("attendance").doc(`${sId}_${caller.id}`).create({
      sessionId: sId,
      studentId: caller.id,
      subjectId: session.subjectId,
      date: session.createdAt,
      slot: session.slot,
      status: "present",
      markedByTeacherId: session.teacherId,
      markedAt: now,
    });
  } catch (e) {
    // ALREADY_EXISTS: scanning twice is fine.
    if (e.code !== 6) throw e;
    return { ok: true, alreadyMarked: true };
  }
  return { ok: true, alreadyMarked: false };
});

// ---------------------------------------------------------------------------
// ADMIN USER MANAGEMENT
// ---------------------------------------------------------------------------
// Creating/deleting Firebase Auth accounts needs the Admin SDK, so it can't be
// done from the client without signing the admin out.

const PROFILE_FIELDS = [
  "role", "name", "email", "phone", "isActive", "collegeRollNo", "examRollNo",
  "section", "year", "qualifications", "idCardPhotoPath", "gender",
  "date_of_birth", "course", "semester", "isAdmin",
];

exports.createUserAccount = onCall(async (request) => {
  const caller = await getCaller(request);
  if (!isAdmin(caller)) throw new HttpsError("permission-denied", "Admins only.");

  const { password, profile } = request.data || {};
  if (!profile || typeof profile.email !== "string" || !profile.email.trim()) {
    throw new HttpsError("invalid-argument", "An email address is required.");
  }
  if (typeof password !== "string" || password.length < 6) {
    throw new HttpsError("invalid-argument", "Password must be at least 6 characters.");
  }
  if (!["student", "teacher", "admin"].includes(profile.role)) {
    throw new HttpsError("invalid-argument", "Invalid role.");
  }

  let authUser;
  try {
    authUser = await admin.auth().createUser({
      email: profile.email.trim(),
      password,
      displayName: profile.name || undefined,
    });
  } catch (e) {
    if (e.code === "auth/email-already-exists") {
      throw new HttpsError("already-exists", "An account with this email already exists.");
    }
    if (e.code === "auth/invalid-email") {
      throw new HttpsError("invalid-argument", "Invalid email address.");
    }
    throw e;
  }

  const doc = { createdAt: FieldValue.serverTimestamp() };
  for (const k of PROFILE_FIELDS) {
    if (profile[k] !== undefined) doc[k] = profile[k];
  }
  doc.email = profile.email.trim();

  try {
    await db.collection("users").doc(authUser.uid).set(doc);
  } catch (e) {
    await admin.auth().deleteUser(authUser.uid).catch(() => {});
    throw e;
  }
  return { uid: authUser.uid };
});

exports.deleteUserAccount = onCall(async (request) => {
  const caller = await getCaller(request);
  if (!isAdmin(caller)) throw new HttpsError("permission-denied", "Admins only.");

  const uid = request.data && request.data.uid;
  if (typeof uid !== "string" || !uid) {
    throw new HttpsError("invalid-argument", "Missing uid.");
  }
  if (uid === caller.id) {
    throw new HttpsError("failed-precondition", "You cannot delete your own account.");
  }

  try {
    await admin.auth().deleteUser(uid);
  } catch (e) {
    // Profiles created before this function existed have no Auth account.
    if (e.code !== "auth/user-not-found") throw e;
  }
  await db.collection("users").doc(uid).delete();
  return { ok: true };
});

// ---------------------------------------------------------------------------
// IN-APP NOTIFICATIONS
// ---------------------------------------------------------------------------
// FirestoreNotifier queues a request; this fans it out into one
// `notifications` doc per recipient, which NotificationSyncService listens to.

const MAX_NOTIFICATION_TARGETS = 1000;

exports.processNotificationRequest = onDocumentCreated(
  "notification_requests/{requestId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const req = snap.data();

    const requester = await db.collection("users").doc(req.requestedBy || "_").get();
    const r = requester.exists ? requester.data() : null;
    if (!r || r.isActive === false || !(r.role === "teacher" || isAdmin(r))) {
      await snap.ref.update({ status: "rejected" });
      return;
    }

    const targets = Array.isArray(req.targetUserIds) ?
      [...new Set(req.targetUserIds)].slice(0, MAX_NOTIFICATION_TARGETS) :
      [];
    const createdAt = FieldValue.serverTimestamp();

    for (let i = 0; i < targets.length; i += 450) {
      const batch = db.batch();
      for (const userId of targets.slice(i, i + 450)) {
        batch.set(db.collection("notifications").doc(), {
          userId,
          title: String(req.title || ""),
          body: String(req.body || ""),
          type: String(req.type || "general"),
          read: false,
          createdAt,
          data: req.data || null,
        });
      }
      await batch.commit();
    }
    await snap.ref.update({ status: "sent", sentCount: targets.length });
  },
);
