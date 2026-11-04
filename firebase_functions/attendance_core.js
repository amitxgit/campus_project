// functions/attendance_core.js
// Attendance marking shared by QR scans and biometric (fingerprint / face) devices.
//
// Everything here is plain logic that takes a Firestore-like `db` and a
// `serverTimestamp()` sentinel, so it can be unit-tested without Firebase.
// index.js wires it to Cloud Functions triggers and the HTTP endpoint.

const crypto = require("crypto");

const DEFAULT_UTC_OFFSET_MINUTES = 330; // India Standard Time
const EARLY_MINUTES = 15; // a punch up to 15 minutes before class counts for that class
const QR_MAX_AGE_MS = 15000; // same window the app shows students
const QR_MAX_SKEW_MS = 5000; // allow a teacher phone clock slightly ahead of the server

// Sources that Batchwise sets automatically. A record without one of these was
// saved by a teacher or admin, and automatic marking never overwrites it.
const AUTO_SOURCES = new Set(["qr", "biometric"]);

// ---------------------------------------------------------------------------
// Time helpers (institute-local time, e.g. IST)
// ---------------------------------------------------------------------------

/** Minutes since midnight for "HH:MM". Returns null if malformed. */
function parseHHMM(text) {
  const m = /^(\d{1,2}):(\d{2})$/.exec(String(text || "").trim());
  if (!m) return null;
  const h = Number(m[1]);
  const min = Number(m[2]);
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}

/** "08:30-09:30" -> { start: 510, end: 570 } in minutes, or null. */
function parseSlot(slot) {
  const parts = String(slot || "").split("-");
  if (parts.length !== 2) return null;
  const start = parseHHMM(parts[0]);
  const end = parseHHMM(parts[1]);
  if (start === null || end === null || end <= start) return null;
  return { start, end };
}

/** Local calendar date ("YYYY-MM-DD") and minutes since local midnight for an instant. */
function localParts(date, offsetMinutes = DEFAULT_UTC_OFFSET_MINUTES) {
  const shifted = new Date(date.getTime() + offsetMinutes * 60000);
  const dateKey = shifted.toISOString().slice(0, 10);
  const minutes = shifted.getUTCHours() * 60 + shifted.getUTCMinutes();
  return { dateKey, minutes };
}

/** UTC instants for the start and end of a local day. */
function localDayBounds(dateKey, offsetMinutes = DEFAULT_UTC_OFFSET_MINUTES) {
  const startUtc = new Date(`${dateKey}T00:00:00Z`).getTime() - offsetMinutes * 60000;
  return { start: new Date(startUtc), end: new Date(startUtc + 24 * 3600000) };
}

/** Device clock text "YYYY-MM-DD HH:MM:SS" (local time, no zone) -> Date. */
function parseDeviceTime(text, offsetMinutes = DEFAULT_UTC_OFFSET_MINUTES) {
  const m = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?$/.exec(String(text || "").trim());
  if (!m) return null;
  const asUtc = Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +(m[6] || 0));
  if (Number.isNaN(asUtc)) return null;
  return new Date(asUtc - offsetMinutes * 60000);
}

function toDate(value) {
  if (!value) return null;
  if (value instanceof Date) return value;
  if (typeof value.toDate === "function") return value.toDate();
  if (typeof value === "number") return new Date(value);
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

/** Does a punch at `at` belong to this session's class? Same local day, within the slot (or just before). */
function sessionCoversPunch(session, at, offsetMinutes = DEFAULT_UTC_OFFSET_MINUTES) {
  const slot = parseSlot(session.slot);
  const created = toDate(session.createdAt);
  if (!slot || !created || !at) return false;
  const punch = localParts(at, offsetMinutes);
  const day = localParts(created, offsetMinutes);
  if (punch.dateKey !== day.dateKey) return false;
  return punch.minutes >= slot.start - EARLY_MINUTES && punch.minutes < slot.end;
}

// ---------------------------------------------------------------------------
// Marking
// ---------------------------------------------------------------------------

/**
 * Mark a student present for a session, unless a teacher or admin has already
 * set their status by hand. Uses the same document id the teacher's review
 * screen uses ("<sessionId>_<studentId>"), so the two never duplicate.
 * Returns "marked", "already" or "manual".
 */
async function markPresent(db, serverTimestamp, { sessionId, session, studentId, source, method, at }) {
  const ref = db.collection("attendance").doc(`${sessionId}_${studentId}`);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists) {
      const existing = snap.data() || {};
      if (!AUTO_SOURCES.has(existing.source)) return "manual";
      if (existing.status === "present") return "already";
    }
    tx.set(ref, {
      sessionId,
      studentId,
      subjectId: session.subjectId || "",
      date: toDate(session.createdAt) || new Date(),
      slot: session.slot || "",
      status: "present",
      markedByTeacherId: session.teacherId || "",
      markedAt: serverTimestamp(),
      source,
      method: method || source,
      punchedAt: at || null,
    }, { merge: true });
    return "marked";
  });
}

// ---------------------------------------------------------------------------
// QR scans
// ---------------------------------------------------------------------------

/** The signature the teacher's app puts in each QR code (see generate_qr_page.dart). */
function qrSignature(sessionId, ts, teacherId) {
  const secret = `campus_track_secret_${teacherId}`;
  return crypto.createHash("sha256").update(`${sessionId}:${ts}:${secret}`).digest("hex").substring(0, 16);
}

/**
 * Check a student's scan against server time, the code's signature and the
 * session. Returns { ok: true } or { ok: false, reason }.
 */
function verifyQrScan({ scan, session, student, receivedAtMs }) {
  let payload;
  try {
    payload = typeof scan.payload === "string" ? JSON.parse(scan.payload) : scan.payload;
  } catch (e) {
    return { ok: false, reason: "unreadable-code" };
  }
  if (!payload || payload.sId !== scan.sessionId) return { ok: false, reason: "wrong-session" };
  if (!session) return { ok: false, reason: "session-not-found" };
  if (session.isActive === false) return { ok: false, reason: "session-closed" };
  const ts = Number(payload.ts);
  if (!Number.isFinite(ts)) return { ok: false, reason: "unreadable-code" };
  const age = receivedAtMs - ts;
  if (age > QR_MAX_AGE_MS || age < -QR_MAX_SKEW_MS) return { ok: false, reason: "expired" };
  if (payload.sig !== qrSignature(scan.sessionId, ts, session.teacherId)) return { ok: false, reason: "bad-signature" };
  if (!student || student.role !== "student") return { ok: false, reason: "not-a-student" };
  if (student.isActive === false) return { ok: false, reason: "inactive-student" };
  if (student.section !== session.section) return { ok: false, reason: "wrong-section" };
  return { ok: true };
}

// ---------------------------------------------------------------------------
// Biometric devices
// ---------------------------------------------------------------------------

// ZKTeco / eSSL "verify mode" codes for the common methods.
const VERIFY_METHODS = { 0: "password", 1: "fingerprint", 2: "card", 3: "password", 4: "card", 15: "face", 25: "palm" };

/**
 * Parse an ATTLOG upload from a ZKTeco / eSSL device (ADMS push protocol).
 * Each line: PIN <tab> YYYY-MM-DD HH:MM:SS <tab> status <tab> verify <tab> ...
 */
function parseAttlog(body) {
  return String(body || "")
    .split(/\r?\n/)
    .map((line) => line.split("\t").map((s) => s.trim()))
    .filter((cols) => cols.length >= 2 && cols[0] && cols[1])
    .map((cols) => ({
      pin: cols[0],
      time: cols[1],
      method: VERIFY_METHODS[Number(cols[3])] || "biometric",
    }));
}

/** Reply to a device's first contact (GET /iclock/cdata). Asks it to push attendance logs in real time. */
function handshakeResponse(serial) {
  return [
    `GET OPTION FROM: ${serial}`,
    "ATTLOGStamp=None",
    "OPERLOGStamp=9999",
    "ATTPHOTOStamp=None",
    "ErrorDelay=30",
    "Delay=10",
    "TransTimes=00:00;14:05",
    "TransInterval=1",
    "TransFlag=TransData AttLog",
    "Realtime=1",
    "Encrypt=None",
  ].join("\n");
}

/** Find the student a device user id belongs to: biometricId first, then college roll number. */
async function findStudentByPin(db, pin) {
  for (const field of ["biometricId", "collegeRollNo"]) {
    const snap = await db.collection("users")
      .where("role", "==", "student")
      .where(field, "==", pin)
      .limit(2)
      .get();
    if (snap.size === 1) return { id: snap.docs[0].id, ...snap.docs[0].data() };
    if (snap.size > 1) return { ambiguous: true };
  }
  return null;
}

/** Sessions created on the punch's local day, for the student's section, whose slot covers the punch. */
async function sessionsForPunch(db, { section, at, offsetMinutes }) {
  const { dateKey } = localParts(at, offsetMinutes);
  const { start, end } = localDayBounds(dateKey, offsetMinutes);
  const snap = await db.collection("attendance_sessions")
    .where("createdAt", ">=", start)
    .where("createdAt", "<", end)
    .get();
  return snap.docs
    .map((d) => ({ id: d.id, ...d.data() }))
    .filter((s) => s.section === section && sessionCoversPunch(s, at, offsetMinutes));
}

/**
 * Store one punch and mark the student present in any class it belongs to.
 * Punches are stored even when no class is running yet; onSessionCreated
 * applies them when the teacher starts the class.
 */
async function ingestPunch(db, serverTimestamp, { device, deviceId, pin, at, method }) {
  const offsetMinutes = Number.isFinite(device.utcOffsetMinutes) ? device.utcOffsetMinutes : DEFAULT_UTC_OFFSET_MINUTES;
  const student = await findStudentByPin(db, pin);
  const { dateKey } = localParts(at, offsetMinutes);
  const punchId = `${deviceId}_${pin}_${at.getTime()}`.replace(/[^A-Za-z0-9_-]/g, "-");

  const punch = {
    deviceId,
    pin,
    at,
    dateKey,
    method,
    studentId: student && !student.ambiguous ? student.id : null,
    section: student && !student.ambiguous ? student.section || null : null,
    matched: !!(student && !student.ambiguous),
    reason: !student ? "unknown-user" : student.ambiguous ? "ambiguous-user" : null,
    receivedAt: serverTimestamp(),
  };
  await db.collection("biometric_punches").doc(punchId).set(punch, { merge: true });
  if (!punch.matched || student.isActive === false) return { matched: false, marked: 0 };

  const sessions = await sessionsForPunch(db, { section: student.section, at, offsetMinutes });
  let marked = 0;
  for (const s of sessions) {
    const result = await markPresent(db, serverTimestamp, {
      sessionId: s.id, session: s, studentId: student.id, source: "biometric", method, at,
    });
    if (result === "marked") marked += 1;
  }
  return { matched: true, marked };
}

/** When a teacher starts a class, apply punches already received for that class. */
async function applyEarlierPunches(db, serverTimestamp, { sessionId, session, offsetMinutes = DEFAULT_UTC_OFFSET_MINUTES }) {
  const created = toDate(session.createdAt);
  if (!created || !session.section) return 0;
  const { dateKey } = localParts(created, offsetMinutes);
  const snap = await db.collection("biometric_punches")
    .where("dateKey", "==", dateKey)
    .where("section", "==", session.section)
    .get();
  let marked = 0;
  const seen = new Set();
  for (const doc of snap.docs) {
    const p = doc.data();
    const at = toDate(p.at);
    if (!p.matched || !p.studentId || seen.has(p.studentId)) continue;
    if (!sessionCoversPunch(session, at, offsetMinutes)) continue;
    seen.add(p.studentId);
    const result = await markPresent(db, serverTimestamp, {
      sessionId, session, studentId: p.studentId, source: "biometric", method: p.method, at,
    });
    if (result === "marked") marked += 1;
  }
  return marked;
}

module.exports = {
  DEFAULT_UTC_OFFSET_MINUTES,
  parseSlot,
  localParts,
  localDayBounds,
  parseDeviceTime,
  sessionCoversPunch,
  markPresent,
  qrSignature,
  verifyQrScan,
  parseAttlog,
  handshakeResponse,
  findStudentByPin,
  ingestPunch,
  applyEarlierPunches,
};
