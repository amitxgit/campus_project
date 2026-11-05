// functions/index.js
// Cloud Functions v2 (Node 18/20/22)
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { setGlobalOptions } = require("firebase-functions/v2/options");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const crypto = require("crypto");
const checkin = require("./checkin");

admin.initializeApp();
const db = admin.firestore();

// Same region as the Firestore database (Mumbai). Firestore triggers must run
// there, and the app calls functions in this region (see kFunctionsRegion in
// lib/main.dart).
setGlobalOptions({ region: "asia-south1", maxInstances: 10 });

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

  // Short code that identifies this session in the Bluetooth broadcast.
  // Unique among active sessions; collisions are rare (32 bits), so retry.
  let bleCode = checkin.newBleCode();
  for (let i = 0; i < 5; i++) {
    const clash = await db.collection("attendance_sessions")
      .where("bleCode", "==", bleCode).where("isActive", "==", true).limit(1).get();
    if (clash.empty) break;
    bleCode = checkin.newBleCode();
  }

  const batch = db.batch();
  batch.set(ref, {
    teacherId: caller.id,
    subjectId: entry.subjectId,
    section: entry.section,
    slot: `${entry.startTime}-${entry.endTime}`,
    createdAt,
    isActive: true,
    bleCode,
    // The teacher can switch to Bluetooth only, which turns QR scans off.
    qrEnabled: true,
  });
  // Clients have no access to this subcollection (see firestore.rules).
  batch.set(ref.collection("private").doc("key"), { secret });
  await batch.commit();

  return { sessionId: ref.id, secret, bleCode, createdAtMs: createdAt.toMillis() };
});

const EXPIRED_MSG =
  "QR code expired. Please scan the live code directly from the teacher's screen.";
const BLE_EXPIRED_MSG = "That check-in signal has expired. Please try again in class.";

// Students check in with either a scanned QR ({sId, n, sig}) or a Bluetooth
// token heard from the teacher's phone ({ble}). Both carry the installation ID
// of the student's phone ({deviceId}) for phone binding (see checkin.js).
exports.markAttendance = onCall(async (request) => {
  const caller = await getCaller(request);
  if (caller.role !== "student") {
    throw new HttpsError("permission-denied", "Only students can mark attendance.");
  }

  const data = request.data || {};
  const devHash = checkin.deviceHash(data.deviceId);
  if (!devHash) {
    throw new HttpsError(
      "failed-precondition",
      "Please update the app to the latest version to mark attendance.",
    );
  }

  // 1. Work out which session the code is for, and its step and signature.
  let sId;
  let step;
  let verify; // (secret) => boolean
  let method;
  let expiredMsg;
  if (data.ble !== undefined) {
    const tok = checkin.parseBleToken(data.ble);
    if (!tok) {
      throw new HttpsError("invalid-argument", "This is not a valid check-in signal.");
    }
    const match = await db.collection("attendance_sessions")
      .where("bleCode", "==", tok.code).where("isActive", "==", true).limit(2).get();
    if (match.empty) {
      throw new HttpsError("failed-precondition", "This attendance session has ended.");
    }
    // In the rare case two live sessions share a code, the signature decides.
    sId = match.docs.length === 1 ? match.docs[0].id : null;
    step = tok.step;
    method = "ble";
    expiredMsg = BLE_EXPIRED_MSG;
    if (sId === null) {
      for (const d of match.docs) {
        const k = await d.ref.collection("private").doc("key").get();
        if (k.exists && checkin.bleSigOk(k.data().secret, d.id, step, tok.sig)) sId = d.id;
      }
      if (sId === null) {
        throw new HttpsError("permission-denied", "This is not a valid check-in signal.");
      }
    }
    const id = sId;
    verify = (secret) => checkin.bleSigOk(secret, id, step, tok.sig);
  } else {
    const { n, sig } = data;
    sId = data.sId;
    if (typeof sId !== "string" || sId.includes("/") || !Number.isInteger(n) || typeof sig !== "string") {
      throw new HttpsError("invalid-argument", "This is not a valid attendance QR code.");
    }
    step = n;
    method = "qr";
    expiredMsg = EXPIRED_MSG;
    const id = sId;
    verify = (secret) => {
      const expected = signStep(secret, id, n);
      return sig.length === expected.length &&
        crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected));
    };
  }

  // 2. Check the session, the signature and freshness.
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
  if (method === "qr" && session.qrEnabled === false) {
    throw new HttpsError(
      "failed-precondition",
      "Your teacher is taking attendance by Bluetooth for this class. Tap \"Check in\" instead of scanning.",
    );
  }
  if (session.section !== caller.section) {
    throw new HttpsError("permission-denied", "This class is not for your section.");
  }
  if (!verify(keySnap.data().secret)) {
    throw new HttpsError(
      "permission-denied",
      method === "ble" ? "This is not a valid check-in signal." : "This is not a valid attendance QR code.",
    );
  }

  // The Bluetooth step is 16 bits; sessions end long before it wraps.
  const serverStep = Math.floor(elapsed / QR_STEP_MS);
  if (step > serverStep + 1 || step < serverStep - QR_MAX_AGE_STEPS) {
    throw new HttpsError("deadline-exceeded", expiredMsg);
  }

  // 3. Phone binding and the attendance record, in one transaction.
  const userRef = db.collection("users").doc(caller.id);
  const deviceRef = sessionRef.collection("devices").doc(devHash);
  const recordRef = db.collection("attendance").doc(`${sId}_${caller.id}`);
  const now = Timestamp.now();

  return db.runTransaction(async (tx) => {
    const [userSnap, deviceSnap, recordSnap] = await Promise.all([
      tx.get(userRef), tx.get(deviceRef), tx.get(recordRef),
    ]);
    const binding = userSnap.get("deviceBinding");
    if (binding && binding.hash && binding.hash !== devHash) {
      throw new HttpsError(
        "permission-denied",
        "Your account is linked to a different phone. Ask your institute to reset your phone link.",
      );
    }
    if (deviceSnap.exists && deviceSnap.get("studentId") !== caller.id) {
      throw new HttpsError(
        "permission-denied",
        "This phone has already marked another student in this class.",
      );
    }
    if (!binding || !binding.hash) {
      tx.update(userRef, { deviceBinding: { hash: devHash, boundAt: now } });
    }
    if (recordSnap.exists) return { ok: true, alreadyMarked: true };

    if (!deviceSnap.exists) {
      tx.create(deviceRef, { studentId: caller.id, at: now });
    }
    tx.create(recordRef, {
      sessionId: sId,
      studentId: caller.id,
      subjectId: session.subjectId,
      date: session.createdAt,
      slot: session.slot,
      status: "present",
      markedByTeacherId: session.teacherId,
      markedAt: now,
      // Same fields as biometric records (attendance_core.js). Not an auto
      // source, so a later fingerprint punch never overwrites it.
      source: method,
      method,
    });
    return { ok: true, alreadyMarked: false };
  });
});

// ---------------------------------------------------------------------------
// ADMIN USER MANAGEMENT
// ---------------------------------------------------------------------------
// Creating/deleting Firebase Auth accounts needs the Admin SDK, so it can't be
// done from the client without signing the admin out.

const PROFILE_FIELDS = [
  "role", "name", "email", "phone", "isActive", "collegeRollNo", "examRollNo",
  "section", "year", "qualifications", "idCardPhotoPath", "gender",
  "date_of_birth", "course", "semester", "isAdmin", "parentName", "parentPhone",
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
  await deletePersonalData(uid);

  // Close their deletion request, if they made one.
  const req = db.collection("deletion_requests").doc(uid);
  if ((await req.get()).exists) {
    await req.update({ status: "done", handledBy: caller.id, handledAt: FieldValue.serverTimestamp() });
  }
  return { ok: true };
});

// What web/delete-account.html promises: notifications, device tokens and
// uploaded files go with the account. Fee, attendance and result records stay
// with the institute (see the privacy policy).
async function deletePersonalData(uid) {
  const notifications = await db.collection("notifications").where("userId", "==", uid).get();
  for (let i = 0; i < notifications.docs.length; i += 450) {
    const batch = db.batch();
    notifications.docs.slice(i, i + 450).forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }
  await db.recursiveDelete(db.collection("userTokens").doc(uid));

  const assignments = await db.collection("assignments").select().get();
  const bucket = admin.storage().bucket();
  for (const a of assignments.docs) {
    await a.ref.collection("submissions").doc(uid).delete();
    await bucket.deleteFiles({ prefix: `submissions/${a.id}/${uid}/` }).catch((e) =>
      logger.warn("Could not delete uploads", { uid, assignment: a.id, error: String(e) }));
  }
}

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


// ---------------------------------------------------------------------------
// PARENT ALERTS (WhatsApp Cloud API)
// ---------------------------------------------------------------------------
// The app queues docs in parent_alerts; this sends each one as a pre-approved
// WhatsApp template and records the outcome. Credentials live in
// secrets/whatsapp, which clients can write but never read.

const ALERT_TEMPLATES = {
  absence: { name: "absence_alert", params: 3 },
  feeReminder: { name: "fee_reminder", params: 5 },
  feeReceipt: { name: "fee_receipt", params: 5 },
  testResult: { name: "test_result", params: 4 },
};
const IST = "Asia/Kolkata";

// Same rules as PhoneNumber.normalize in the app.
function normalizePhone(input) {
  if (!input) return null;
  let digits = String(input).replace(/\D/g, "");
  if (digits.startsWith("00")) digits = digits.substring(2);
  if (digits.length === 11 && digits.startsWith("0")) digits = digits.substring(1);
  if (digits.length === 10) digits = `91${digits}`;
  if (digits.length < 11 || digits.length > 15) return null;
  return digits;
}

async function whatsappConfig() {
  const snap = await db.collection("secrets").doc("whatsapp").get();
  const cfg = snap.exists ? snap.data() : null;
  if (!cfg || !cfg.token || !cfg.phoneNumberId) return null;
  return cfg;
}

async function sendWhatsAppTemplate(cfg, to, templateName, params, language) {
  // apiBase is only overridden by the emulator tests.
  const base = cfg.apiBase || "https://graph.facebook.com/v21.0";
  const res = await fetch(`${base}/${cfg.phoneNumberId}/messages`, {
    method: "POST",
    headers: { "Authorization": `Bearer ${cfg.token}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      messaging_product: "whatsapp",
      to,
      type: "template",
      template: {
        name: templateName,
        language: { code: language || cfg.language || "en" },
        components: params.length ?
          [{ type: "body", parameters: params.map((t) => ({ type: "text", text: String(t) })) }] :
          [],
      },
    }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error((body.error && body.error.message) || `WhatsApp API error ${res.status}`);
  }
  return body.messages && body.messages[0] && body.messages[0].id;
}

exports.processParentAlert = onDocumentCreated("parent_alerts/{alertId}", async (event) => {
  const snap = event.data;
  if (!snap) return;
  const alert = snap.data();
  const done = (fields) => snap.ref.update({ ...fields, processedAt: FieldValue.serverTimestamp() });

  // Only staff (or the server's own absence trigger) may message parents.
  if (alert.requestedBy !== "system") {
    const requester = await db.collection("users").doc(alert.requestedBy || "_").get();
    const r = requester.exists ? requester.data() : null;
    if (!r || r.isActive === false || !(r.role === "teacher" || isAdmin(r))) {
      return done({ status: "rejected" });
    }
  }

  const template = ALERT_TEMPLATES[alert.kind];
  const params = Array.isArray(alert.params) ? alert.params.map(String) : [];
  if (!template || params.length !== template.params) {
    return done({ status: "rejected", error: "Unknown alert type or wrong number of values." });
  }

  const student = await db.collection("users").doc(alert.studentId || "_").get();
  const to = normalizePhone(student.exists && student.data().parentPhone);
  if (!to) return done({ status: "noPhone" });

  const cfg = await whatsappConfig();
  if (!cfg) return done({ status: "notConfigured" });

  try {
    const messageId = await sendWhatsAppTemplate(cfg, to, template.name, params);
    return done({ status: "sent", messageId: messageId || null });
  } catch (e) {
    logger.warn("WhatsApp send failed", { alert: snap.id, error: String(e) });
    return done({ status: "failed", error: String(e.message || e) });
  }
});

// Automatically tells parents when a student is marked absent, at most once
// per student per day, if the institute has switched this on.
exports.autoAbsenceAlert = onDocumentWritten("attendance/{recordId}", async (event) => {
  const after = event.data.after.exists ? event.data.after.data() : null;
  const before = event.data.before.exists ? event.data.before.data() : null;
  if (!after || after.status !== "absent" || (before && before.status === "absent")) return;

  const settingsSnap = await db.collection("settings").doc("institution").get();
  const settings = settingsSnap.exists ? settingsSnap.data() : {};
  if (!settings.parentAlertsEnabled || !settings.autoAbsenceAlerts || !settings.whatsappSender) return;

  const student = await db.collection("users").doc(after.studentId).get();
  if (!student.exists) return;

  const date = after.date && after.date.toDate ? after.date.toDate() : new Date();
  const dayKey = date.toLocaleDateString("en-CA", { timeZone: IST }); // YYYY-MM-DD
  const dayLabel = date.toLocaleDateString("en-IN", { timeZone: IST, day: "numeric", month: "short", year: "numeric" });

  try {
    await db.collection("parent_alerts").doc(`absence_${after.studentId}_${dayKey}`).create({
      studentId: after.studentId,
      studentName: student.data().name || "",
      kind: "absence",
      params: [student.data().name || "Your child", dayLabel, settings.name || "the institute"],
      requestedBy: "system",
      status: "pending",
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (e) {
    if (e.code !== 6) throw e; // ALREADY_EXISTS: parent was already told today
  }
});

// Lets an admin check their WhatsApp setup with Meta's built-in template.
exports.testWhatsApp = onCall(async (request) => {
  const caller = await getCaller(request);
  if (!isAdmin(caller)) throw new HttpsError("permission-denied", "Admins only.");
  const to = normalizePhone(request.data && request.data.to);
  if (!to) throw new HttpsError("invalid-argument", "Enter a valid mobile number.");
  const cfg = await whatsappConfig();
  if (!cfg) throw new HttpsError("failed-precondition", "Save your WhatsApp credentials first.");
  try {
    await sendWhatsAppTemplate(cfg, to, "hello_world", [], "en_US");
  } catch (e) {
    throw new HttpsError("failed-precondition", `WhatsApp rejected the message: ${e.message}`);
  }
  return { ok: true };
});


// ---------------------------------------------------------------------------
// ONLINE FEE PAYMENTS (Razorpay Payment Links)
// ---------------------------------------------------------------------------
// Optional. An admin creates a link for a student's fee; the parent pays it
// and Razorpay calls razorpayWebhook, which records the payment exactly like
// FeeRepository.recordPayment in the app. Keys live in secrets/razorpay
// (write-only for admins, like secrets/whatsapp).

const RAZORPAY_MODES = { upi: "upi", card: "card", netbanking: "bankTransfer" };

async function razorpayConfig() {
  const snap = await db.collection("secrets").doc("razorpay").get();
  const cfg = snap.exists ? snap.data() : null;
  if (!cfg || !cfg.keyId || !cfg.keySecret) return null;
  return cfg;
}

const istDay = (d) => d.toLocaleDateString("en-CA", { timeZone: IST }); // YYYY-MM-DD
const toDate = (v) => (v && v.toDate ? v.toDate() : new Date(v));
const balanceOf = (a) =>
  (Number(a.totalFee) || 0) - (Number(a.discount) || 0) - (Number(a.paidAmount) || 0);

// Same as FeeAccount in the app: payments cover instalments oldest-first;
// `overdue` is what's left on instalments due before today (IST), `next` what's
// left on the first one not yet due.
function feeDue(account, now = new Date()) {
  const today = istDay(now);
  const instalments = (account.instalments || [])
    .map((i) => ({ amount: Number(i.amount) || 0, due: toDate(i.dueDate) }))
    .sort((a, b) => a.due - b.due);
  let remaining = Number(account.paidAmount) || 0;
  let overdue = 0;
  let next = 0;
  for (const inst of instalments) {
    const covered = Math.min(Math.max(remaining, 0), inst.amount);
    remaining -= covered;
    const left = inst.amount - covered;
    if (left <= 0.5) continue;
    if (istDay(inst.due) < today) overdue += left;
    else if (!next) next = left;
  }
  return { overdue, next, hasInstalments: instalments.length > 0 };
}

// Same as FeeAccount.payableNow: everything overdue, else the next instalment.
function payableNow(account, now = new Date()) {
  const { overdue, next, hasInstalments } = feeDue(account, now);
  if (!hasInstalments) return Math.max(balanceOf(account), 0);
  return overdue > 0.5 ? overdue : next;
}

exports.createFeePaymentLink = onCall(async (request) => {
  const caller = await getCaller(request);
  if (!isAdmin(caller)) throw new HttpsError("permission-denied", "Admins only.");
  const { studentId, amount } = request.data || {};
  if (typeof studentId !== "string" || !studentId) {
    throw new HttpsError("invalid-argument", "Missing studentId.");
  }

  const [accountSnap, studentSnap, settingsSnap, cfg] = await Promise.all([
    db.collection("fee_accounts").doc(studentId).get(),
    db.collection("users").doc(studentId).get(),
    db.collection("settings").doc("institution").get(),
    razorpayConfig(),
  ]);
  if (!cfg) throw new HttpsError("failed-precondition", "Connect Razorpay in Settings first.");
  if (!accountSnap.exists) {
    throw new HttpsError("failed-precondition", "Set up a fee plan for this student first.");
  }
  const account = accountSnap.data();

  const ask = amount === undefined || amount === null ? payableNow(account) : Number(amount);
  if (!Number.isFinite(ask) || ask < 1) {
    throw new HttpsError("invalid-argument", "Nothing is due for this student.");
  }
  if (ask > balanceOf(account) + 0.5) {
    throw new HttpsError("invalid-argument", "That is more than the balance.");
  }
  const paise = Math.round(ask * 100);

  const student = studentSnap.exists ? studentSnap.data() : {};
  const name = student.name || account.studentName || "Student";
  const institute = (settingsSnap.exists && settingsSnap.data().name) || "";
  const phone = normalizePhone(student.parentPhone);

  // apiBase is only overridden by the emulator tests.
  const base = cfg.apiBase || "https://api.razorpay.com";
  const auth = Buffer.from(`${cfg.keyId}:${cfg.keySecret}`).toString("base64");
  const res = await fetch(`${base}/v1/payment_links`, {
    method: "POST",
    headers: { "Authorization": `Basic ${auth}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      amount: paise,
      currency: "INR",
      accept_partial: false,
      description: `Fees for ${name}${institute ? `, ${institute}` : ""}`,
      customer: { name: student.parentName || name, ...(phone ? { contact: `+${phone}` } : {}) },
      // The institute sends the link itself (WhatsApp), so Razorpay stays quiet.
      notify: { sms: false, email: false },
      reminder_enable: false,
      notes: { studentId },
    }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok || !body.id || !body.short_url) {
    const msg = (body.error && body.error.description) || `error ${res.status}`;
    logger.warn("Razorpay payment link failed", { studentId, error: msg });
    throw new HttpsError("failed-precondition", `Razorpay rejected the request: ${msg}`);
  }

  await db.collection("payment_links").doc(body.id).set({
    studentId,
    studentName: name,
    amount: paise / 100,
    shortUrl: body.short_url,
    status: "created",
    createdBy: caller.id,
    createdAt: FieldValue.serverTimestamp(),
  });
  return { id: body.id, url: body.short_url, amount: paise / 100 };
});

function validRazorpaySignature(rawBody, signature, secret) {
  if (!rawBody || typeof signature !== "string" || !secret) return false;
  const expected = Buffer.from(crypto.createHmac("sha256", secret).update(rawBody).digest("hex"));
  const given = Buffer.from(signature);
  return expected.length === given.length && crypto.timingSafeEqual(expected, given);
}

// Razorpay Dashboard → Webhooks → this URL, event payment_link.paid. Razorpay
// retries on any non-2xx reply, so failing here is safe: the payment doc id is
// the Razorpay payment id, and a repeat delivery finds it and stops.
exports.razorpayWebhook = onRequest({ invoker: "public" }, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("POST only");
    return;
  }
  const cfg = await razorpayConfig();
  if (!cfg || !validRazorpaySignature(req.rawBody, req.get("X-Razorpay-Signature"), cfg.webhookSecret)) {
    logger.warn("Razorpay webhook with a bad or missing signature");
    res.status(400).send("Invalid signature");
    return;
  }

  const event = req.body || {};
  if (event.event !== "payment_link.paid") {
    res.status(200).send("ignored");
    return;
  }
  const payload = event.payload || {};
  const link = payload.payment_link && payload.payment_link.entity;
  const payment = payload.payment && payload.payment.entity;
  if (!link || !link.id || !payment || !payment.id || !(payment.amount > 0)) {
    res.status(400).send("Missing payment details");
    return;
  }

  // Only links this app created count, so the student comes from our record.
  const linkRef = db.collection("payment_links").doc(link.id);
  const linkSnap = await linkRef.get();
  if (!linkSnap.exists) {
    logger.warn("Razorpay payment for an unknown link", { link: link.id, payment: payment.id });
    res.status(200).send("unknown link");
    return;
  }
  const studentId = linkSnap.data().studentId;
  const accountRef = db.collection("fee_accounts").doc(studentId);
  const paymentRef = accountRef.collection("payments").doc(payment.id);
  const countersRef = db.collection("meta").doc("counters");
  const amount = payment.amount / 100;

  // Same writes as FeeRepository.recordPayment, in one transaction.
  const outcome = await db.runTransaction(async (tx) => {
    const [existing, account, counters] = await Promise.all([
      tx.get(paymentRef), tx.get(accountRef), tx.get(countersRef),
    ]);
    if (existing.exists) return "duplicate";
    if (!account.exists) {
      tx.update(linkRef, { status: "paidNoAccount", paymentId: payment.id, paidAt: FieldValue.serverTimestamp() });
      return "noAccount";
    }
    const receiptNo = ((counters.exists && counters.data().receiptSeq) || 0) + 1;
    tx.set(countersRef, { receiptSeq: receiptNo }, { merge: true });
    tx.set(paymentRef, {
      amount,
      mode: RAZORPAY_MODES[payment.method] || "online",
      reference: payment.id,
      note: "Paid online (Razorpay link)",
      paidOn: Timestamp.fromMillis((payment.created_at || Date.now() / 1000) * 1000),
      receiptNo,
      receivedBy: "Razorpay",
      voided: false,
      paymentLinkId: link.id,
    });
    tx.update(accountRef, { paidAmount: FieldValue.increment(amount), updatedAt: FieldValue.serverTimestamp() });
    tx.update(linkRef, { status: "paid", paymentId: payment.id, receiptNo, paidAt: FieldValue.serverTimestamp() });
    return "recorded";
  });
  if (outcome === "noAccount") {
    logger.error("Razorpay payment for a student with no fee plan", { studentId, payment: payment.id });
  }
  res.status(200).send(outcome);
});

// ---------------------------------------------------------------------------
// OWNER'S DAILY SUMMARY
// ---------------------------------------------------------------------------
// Every evening at 8 pm IST: today's collections, absences, total overdue and
// enquiries. Always an in-app notification to each admin; also a WhatsApp
// message to settings.ownerPhone when WhatsApp is connected.

const DAILY_SUMMARY_TEMPLATE = { name: "daily_summary", params: 6 };

// IST calendar day containing `when`: its key, label and [start, end).
function istDayBounds(when = new Date()) {
  const key = istDay(when);
  const start = new Date(`${key}T00:00:00+05:30`);
  const end = new Date(start.getTime() + 24 * 60 * 60 * 1000);
  const label = start.toLocaleDateString("en-IN", { timeZone: IST, weekday: "short", day: "numeric", month: "short" });
  return { key, start, end, label };
}

const money = (amount, symbol) =>
  `${symbol || "₹"}${Math.round(amount).toLocaleString("en-IN")}`;

const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;

// The figures for one IST day. Pure reads; `day` from istDayBounds.
async function computeDailySummary(day) {
  const [payments, attendance, accounts, enquiries] = await Promise.all([
    db.collectionGroup("payments")
      .where("paidOn", ">=", day.start).where("paidOn", "<", day.end).get(),
    db.collection("attendance")
      .where("date", ">=", day.start).where("date", "<", day.end).get(),
    db.collection("fee_accounts").get(),
    db.collection("enquiries").where("createdAt", ">=", day.start).where("createdAt", "<", day.end).get(),
  ]);
  // Open enquiries due today or earlier that nobody touched today.
  const due = await db.collection("enquiries").where("nextFollowUp", "<", day.end).get();

  const valid = payments.docs.map((d) => d.data()).filter((p) => !p.voided);
  const absent = new Set(attendance.docs.map((d) => d.data())
    .filter((r) => r.status === "absent").map((r) => r.studentId));
  // Instalments falling due today aren't overdue until tomorrow.
  const overdue = accounts.docs.reduce((sum, d) => sum + feeDue(d.data(), day.start).overdue, 0);
  const missed = due.docs.map((d) => d.data()).filter((e) =>
    e.status !== "joined" && e.status !== "lost" &&
    !(e.updatedAt && toDate(e.updatedAt) >= day.start));

  return {
    date: day.key,
    collected: valid.reduce((s, p) => s + (Number(p.amount) || 0), 0),
    payments: valid.length,
    absent: absent.size,
    overdue,
    newEnquiries: enquiries.size,
    missedFollowUps: missed.length,
  };
}

// The six daily_summary template values (no line breaks: WhatsApp rejects them).
function dailySummaryParams(s, label, institute, symbol) {
  return [
    label,
    institute || "your institute",
    s.payments ? `${money(s.collected, symbol)} from ${plural(s.payments, "payment", "payments")}` : "nil",
    String(s.absent),
    money(s.overdue, symbol),
    `${s.newEnquiries} new, ${s.missedFollowUps} follow-up${s.missedFollowUps === 1 ? "" : "s"} missed`,
  ];
}

async function activeAdminIds() {
  const [byRole, byFlag] = await Promise.all([
    db.collection("users").where("role", "==", "admin").get(),
    db.collection("users").where("isAdmin", "==", true).get(),
  ]);
  return [...new Set([...byRole.docs, ...byFlag.docs]
    .filter((d) => d.data().isActive !== false).map((d) => d.id))];
}

// Computes, stores (daily_summaries/{day}) and delivers a day's summary.
// With onlyOnce, a day that already has a summary is skipped (scheduler retries).
async function runDailySummary(when, { onlyOnce = false } = {}) {
  const day = istDayBounds(when);
  const ref = db.collection("daily_summaries").doc(day.key);
  if (onlyOnce && (await ref.get()).exists) return { skipped: true, date: day.key };

  const settings = (await db.collection("settings").doc("institution").get()).data() || {};
  const summary = await computeDailySummary(day);
  const params = dailySummaryParams(summary, day.label, settings.name, settings.currencySymbol);

  const admins = await activeAdminIds();
  const batch = db.batch();
  for (const userId of admins) {
    batch.set(db.collection("notifications").doc(), {
      userId,
      title: `Today at ${settings.name || "your institute"} · ${day.label}`,
      body: `Collected ${params[2]}. ${plural(summary.absent, "student", "students")} absent. ` +
        `Overdue ${params[4]}. Enquiries: ${params[5]}.`,
      type: "dailySummary",
      read: false,
      createdAt: FieldValue.serverTimestamp(),
      data: { date: day.key },
    });
  }
  await batch.commit();

  let whatsapp = "off";
  const to = normalizePhone(settings.ownerPhone);
  if (to && settings.whatsappSender) {
    const cfg = await whatsappConfig();
    if (cfg) {
      try {
        await sendWhatsAppTemplate(cfg, to, DAILY_SUMMARY_TEMPLATE.name, params);
        whatsapp = "sent";
      } catch (e) {
        logger.warn("Daily summary WhatsApp failed", { error: String(e) });
        whatsapp = `failed: ${e.message || e}`;
      }
    }
  }

  const result = { ...summary, params, notified: admins.length, whatsapp };
  await ref.set({ ...result, createdAt: FieldValue.serverTimestamp() });
  return result;
}

exports.dailySummary = onSchedule(
  { schedule: "0 20 * * *", timeZone: IST, retryCount: 2 },
  async () => {
    const r = await runDailySummary(new Date(), { onlyOnce: true });
    logger.info("Daily summary", r);
  },
);

// "Send now" from the app; admins may also pass a past day (YYYY-MM-DD).
exports.sendDailySummary = onCall(async (request) => {
  const caller = await getCaller(request);
  if (!isAdmin(caller)) throw new HttpsError("permission-denied", "Admins only.");
  const date = request.data && request.data.date;
  if (date !== undefined && !/^\d{4}-\d{2}-\d{2}$/.test(String(date))) {
    throw new HttpsError("invalid-argument", "Date must look like 2026-11-02.");
  }
  // Midday IST of that date, so the IST day is unambiguous.
  return runDailySummary(date ? new Date(`${date}T12:00:00+05:30`) : new Date());
});

// ---------------------------------------------------------------------------
// BULK STUDENT IMPORT
// ---------------------------------------------------------------------------
// Students without an email sign in with their mobile number, which maps to
// an internal address on this domain (see LoginId in the app).
const PHONE_LOGIN_DOMAIN = "students.batchwise.app";
const MAX_IMPORT_ROWS = 200;

function generatePassword() {
  // No look-alike characters (0/O, 1/l/I), easy to read out to a student.
  const chars = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = crypto.randomBytes(8);
  return Array.from(bytes, (b) => chars[b % chars.length]).join("");
}

function loginEmailFor(email, phone) {
  if (email && String(email).trim()) return String(email).trim().toLowerCase();
  const p = normalizePhone(phone);
  return p ? `${p.slice(-10)}@${PHONE_LOGIN_DOMAIN}` : null;
}

exports.bulkCreateStudents = onCall({ timeoutSeconds: 300 }, async (request) => {
  const caller = await getCaller(request);
  if (!isAdmin(caller)) throw new HttpsError("permission-denied", "Admins only.");
  const rows = request.data && request.data.rows;
  if (!Array.isArray(rows) || rows.length === 0 || rows.length > MAX_IMPORT_ROWS) {
    throw new HttpsError("invalid-argument", `Send between 1 and ${MAX_IMPORT_ROWS} rows at a time.`);
  }

  const results = [];
  // Sequential on purpose: Auth limits how fast accounts can be created.
  for (const row of rows) {
    const name = String(row.name || "").trim();
    const section = String(row.section || "").trim();
    const login = loginEmailFor(row.email, row.phone);
    const provided = row.password ? String(row.password) : "";
    if (!name || !section || !login) {
      results.push({ ok: false, error: "Name, batch and an email or mobile number are required." });
      continue;
    }
    if (provided && provided.length < 6) {
      results.push({ ok: false, login, error: "Password must be at least 6 characters." });
      continue;
    }
    const password = provided || generatePassword();
    try {
      const user = await admin.auth().createUser({ email: login, password, displayName: name });
      await db.collection("users").doc(user.uid).set({
        role: "student",
        name,
        email: login,
        phone: String(row.phone || "").trim(),
        section,
        collegeRollNo: String(row.rollNo || "").trim() || null,
        parentName: String(row.parentName || "").trim() || null,
        parentPhone: String(row.parentPhone || "").trim() || null,
        isActive: true,
        isAdmin: false,
        qualifications: [],
        createdAt: FieldValue.serverTimestamp(),
      });
      results.push({ ok: true, uid: user.uid, login, password: provided ? null : password });
    } catch (e) {
      const error = e.code === "auth/email-already-exists" ?
        "An account with this email/mobile already exists." :
        e.code === "auth/invalid-email" ? "Invalid email address." : String(e.message || e);
      results.push({ ok: false, login, error });
    }
  }
  return { results };
});

// Admins set a new password directly, e.g. for students who sign in with a
// mobile number and so can't receive a reset email.
exports.setUserPassword = onCall(async (request) => {
  const caller = await getCaller(request);
  if (!isAdmin(caller)) throw new HttpsError("permission-denied", "Admins only.");
  const { uid, password } = request.data || {};
  if (typeof uid !== "string" || !uid) throw new HttpsError("invalid-argument", "Missing uid.");
  if (typeof password !== "string" || password.length < 6) {
    throw new HttpsError("invalid-argument", "Password must be at least 6 characters.");
  }
  try {
    await admin.auth().updateUser(uid, { password });
  } catch (e) {
    if (e.code === "auth/user-not-found") throw new HttpsError("not-found", "This user has no login.");
    throw e;
  }
  return { ok: true };
});

// ---------------------------------------------------------------------------
// FINGERPRINT AND FACE-SCAN ATTENDANCE
// ---------------------------------------------------------------------------
// ZKTeco / eSSL machines push punches to `biometric` (ADMS protocol); other
// systems POST JSON to /punches. A punch marks the student present in the
// class running at that time. See BIOMETRIC.md for setup.
const attendanceCore = require("./attendance_core");
const { handleBiometricRequest } = require("./biometric_http");

const serverTimestamp = () => FieldValue.serverTimestamp();

exports.biometric = onRequest({ invoker: "public" }, async (req, res) => {
  try {
    const result = await handleBiometricRequest(db, serverTimestamp, {
      method: req.method,
      path: req.path,
      query: req.query,
      headers: req.headers,
      body: req.is("application/json") ? req.body : undefined,
      rawBody: req.rawBody ? req.rawBody.toString("utf8") : "",
    });
    res.status(result.status).type(result.contentType).send(result.body);
  } catch (e) {
    logger.error("biometric endpoint error", { error: String(e) });
    res.status(500).type("text/plain").send("ERROR");
  }
});

// When a teacher starts a class, apply punches already received for it.
exports.applyBiometricOnSessionStart = onDocumentCreated("attendance_sessions/{sessionId}", async (event) => {
  const snap = event.data;
  if (!snap) return;
  const marked = await attendanceCore.applyEarlierPunches(db, serverTimestamp, {
    sessionId: event.params.sessionId, session: snap.data() || {},
  });
  if (marked) logger.info("biometric punches applied", { sessionId: event.params.sessionId, marked });
});
