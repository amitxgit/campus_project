// functions/index.js
// Cloud Functions v2 (Node 18/20/22)
const { onCall } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2/options");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

admin.initializeApp();

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
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
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
        } catch (e) {}
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
// Attendance: QR scans and biometric (fingerprint / face) devices
// See BIOMETRIC.md for device setup.
// ---------------------------------------------------------------------------
const { onRequest } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentCreatedWithAuthContext } = require("firebase-functions/v2/firestore");
const attendanceCore = require("./attendance_core");
const { handleBiometricRequest } = require("./biometric_http");

const serverTimestamp = () => admin.firestore.FieldValue.serverTimestamp();

// A student's app writes attendance_scans/<id> after scanning the teacher's QR code.
// This checks the code against server time (not the phone's clock), its signature,
// and the student's section, then marks them present.
exports.verifyQrScan = onDocumentCreatedWithAuthContext("attendance_scans/{scanId}", async (event) => {
  const snap = event.data;
  if (!snap) return;
  const scan = snap.data() || {};
  const db = admin.firestore();
  const finish = (status, reason = null) =>
    snap.ref.set({ status, reason, checkedAt: serverTimestamp() }, { merge: true });

  // The signed-in user must be the student the scan is for.
  if (event.authType !== "system" && event.authId && event.authId !== scan.studentId) {
    return finish("rejected", "wrong-user");
  }
  const [sessionSnap, studentSnap] = await Promise.all([
    db.collection("attendance_sessions").doc(String(scan.sessionId || "-")).get(),
    db.collection("users").doc(String(scan.studentId || "-")).get(),
  ]);
  const session = sessionSnap.exists ? sessionSnap.data() : null;
  const student = studentSnap.exists ? studentSnap.data() : null;
  const check = attendanceCore.verifyQrScan({
    scan, session, student, receivedAtMs: snap.createTime.toMillis(),
  });
  if (!check.ok) return finish("rejected", check.reason);

  const result = await attendanceCore.markPresent(db, serverTimestamp, {
    sessionId: scan.sessionId, session, studentId: scan.studentId, source: "qr", method: "qr", at: snap.createTime.toDate(),
  });
  return finish(result === "manual" ? "kept-teacher-mark" : "accepted");
});

// When a teacher starts a class, apply fingerprint / face punches already received for it.
exports.applyBiometricOnSessionStart = onDocumentCreated("attendance_sessions/{sessionId}", async (event) => {
  const snap = event.data;
  if (!snap) return;
  const marked = await attendanceCore.applyEarlierPunches(admin.firestore(), serverTimestamp, {
    sessionId: event.params.sessionId, session: snap.data() || {},
  });
  if (marked) logger.info("biometric punches applied", { sessionId: event.params.sessionId, marked });
});

// Endpoint for attendance devices. Point a ZKTeco / eSSL device's cloud server
// setting at this function's URL; other systems can POST JSON to /punches.
exports.biometric = onRequest({ cors: false }, async (req, res) => {
  try {
    const result = await handleBiometricRequest(admin.firestore(), serverTimestamp, {
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
