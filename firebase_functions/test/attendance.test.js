// Run with: npm test   (from firebase_functions/)
const test = require("node:test");
const assert = require("node:assert/strict");
const core = require("../attendance_core");
const { handleBiometricRequest } = require("../biometric_http");

// --- Minimal in-memory Firestore stand-in ------------------------------------
function fakeDb() {
  const data = {}; // { collection: { id: doc } }
  const col = (name) => (data[name] = data[name] || {});
  const cmp = { "==": (a, b) => a === b, ">=": (a, b) => a >= b, "<": (a, b) => a < b };
  const snapOf = (name, id) => {
    const d = col(name)[id];
    return { id, exists: d !== undefined, data: () => (d ? { ...d } : undefined) };
  };
  const docRef = (name, id) => ({
    id,
    get: async () => snapOf(name, id),
    set: async (value, opts) => {
      col(name)[id] = opts && opts.merge ? { ...(col(name)[id] || {}), ...value } : { ...value };
    },
    _path: [name, id],
  });
  const query = (name, filters = [], lim = Infinity) => ({
    where: (f, op, v) => query(name, [...filters, [f, op, v]], lim),
    limit: (n) => query(name, filters, n),
    get: async () => {
      const docs = Object.keys(col(name))
        .filter((id) => filters.every(([f, op, v]) => {
          const x = col(name)[id][f];
          const a = x instanceof Date ? x.getTime() : x;
          const b = v instanceof Date ? v.getTime() : v;
          return a !== undefined && a !== null && cmp[op](a, b);
        }))
        .slice(0, lim)
        .map((id) => snapOf(name, id));
      return { docs, size: docs.length };
    },
  });
  return {
    data,
    collection: (name) => ({ doc: (id) => docRef(name, id), ...query(name) }),
    runTransaction: async (fn) => fn({
      get: (ref) => ref.get(),
      set: (ref, value, opts) => ref.set(value, opts),
    }),
  };
}
const TS = () => "SERVER_TS";
const ist = (s) => new Date(`${s}+05:30`); // "2026-11-04T09:05:00" in India time

function seed(db) {
  db.data.users = {
    stu1: { role: "student", name: "Asha", section: "A", collegeRollNo: "21CS045" },
    stu2: { role: "student", name: "Ravi", section: "B", collegeRollNo: "21CS046" },
    stu3: { role: "student", name: "Meera", section: "A", collegeRollNo: "21CS047", biometricId: "7" },
  };
  db.data.biometric_devices = {
    ZK123: { enabled: true, name: "Gate 1" },
    gateway: { enabled: true, apiKey: "secret-key" },
  };
}
const session = (over = {}) => ({
  teacherId: "t1", subjectId: "math", section: "A", slot: "09:00-10:00",
  createdAt: ist("2026-11-04T08:58:00"), isActive: true, ...over,
});
const attlog = (rows) => ({
  method: "POST", path: "/iclock/cdata", query: { SN: "ZK123", table: "ATTLOG" }, headers: {},
  rawBody: rows.map((r) => r.join("\t")).join("\n"),
});

// --- Time helpers -------------------------------------------------------------
test("slots and device times are read in India time", () => {
  assert.deepEqual(core.parseSlot("08:30-09:30"), { start: 510, end: 570 });
  assert.equal(core.parseSlot("bad"), null);
  assert.equal(core.parseDeviceTime("2026-11-04 09:05:00").toISOString(), "2026-11-04T03:35:00.000Z");
  assert.ok(core.sessionCoversPunch(session(), ist("2026-11-04T08:50:00")), "15 minutes early counts");
  assert.ok(!core.sessionCoversPunch(session(), ist("2026-11-04T08:40:00")), "25 minutes early does not");
  assert.ok(!core.sessionCoversPunch(session(), ist("2026-11-04T10:00:00")), "after the slot does not");
  assert.ok(!core.sessionCoversPunch(session(), ist("2026-11-05T09:10:00")), "next day does not");
});

// --- Biometric devices ----------------------------------------------------------
test("a fingerprint punch during class marks the student present", async () => {
  const db = fakeDb(); seed(db);
  db.data.attendance_sessions = { s1: session() };
  const res = await handleBiometricRequest(db, TS, attlog([["21CS045", "2026-11-04 09:05:00", "0", "1"]]));
  assert.equal(res.status, 200);
  assert.equal(res.body, "OK: 1");
  const rec = db.data.attendance.s1_stu1;
  assert.equal(rec.status, "present");
  assert.equal(rec.source, "biometric");
  assert.equal(rec.method, "fingerprint");
  assert.equal(rec.slot, "09:00-10:00");
});

test("a face punch maps through biometricId before roll number", async () => {
  const db = fakeDb(); seed(db);
  db.data.attendance_sessions = { s1: session() };
  await handleBiometricRequest(db, TS, attlog([["7", "2026-11-04 09:10:00", "0", "15"]]));
  assert.equal(db.data.attendance.s1_stu3.method, "face");
});

test("a punch before the teacher starts class is applied when the class starts", async () => {
  const db = fakeDb(); seed(db);
  await handleBiometricRequest(db, TS, attlog([["21CS045", "2026-11-04 08:52:00", "0", "1"]]));
  assert.equal(db.data.attendance, undefined, "nothing to mark yet");
  const s = session({ createdAt: ist("2026-11-04T09:03:00") });
  db.data.attendance_sessions = { s9: s };
  const marked = await core.applyEarlierPunches(db, TS, { sessionId: "s9", session: s });
  assert.equal(marked, 1);
  assert.equal(db.data.attendance.s9_stu1.status, "present");
});

test("students from another section are not marked", async () => {
  const db = fakeDb(); seed(db);
  db.data.attendance_sessions = { s1: session() };
  await handleBiometricRequest(db, TS, attlog([["21CS046", "2026-11-04 09:05:00", "0", "1"]]));
  assert.equal(db.data.attendance, undefined);
});

test("a teacher's manual mark is never overwritten", async () => {
  const db = fakeDb(); seed(db);
  db.data.attendance_sessions = { s1: session() };
  db.data.attendance = { s1_stu1: { status: "excused", studentId: "stu1" } }; // saved from the review screen
  await handleBiometricRequest(db, TS, attlog([["21CS045", "2026-11-04 09:05:00", "0", "1"]]));
  assert.equal(db.data.attendance.s1_stu1.status, "excused");
});

test("unknown devices are recorded for approval and their punches ignored", async () => {
  const db = fakeDb(); seed(db);
  db.data.attendance_sessions = { s1: session() };
  const hello = await handleBiometricRequest(db, TS, { method: "GET", path: "/iclock/cdata", query: { SN: "NEW9" }, headers: {} });
  assert.match(hello.body, /GET OPTION FROM: NEW9/);
  assert.equal(db.data.biometric_devices.NEW9.enabled, false);
  const res = await handleBiometricRequest(db, TS, { ...attlog([["21CS045", "2026-11-04 09:05:00", "0", "1"]]), query: { SN: "NEW9", table: "ATTLOG" } });
  assert.equal(res.body, "OK: 0");
  assert.equal(db.data.biometric_punches, undefined);
});

test("unknown device users are stored as unmatched punches", async () => {
  const db = fakeDb(); seed(db);
  await handleBiometricRequest(db, TS, attlog([["99999", "2026-11-04 09:05:00", "0", "1"]]));
  const [punch] = Object.values(db.data.biometric_punches);
  assert.equal(punch.matched, false);
  assert.equal(punch.reason, "unknown-user");
});

test("the JSON endpoint needs the device's key", async () => {
  const db = fakeDb(); seed(db);
  db.data.attendance_sessions = { s1: session() };
  const body = { deviceId: "gateway", punches: [{ userId: "21CS045", time: "2026-11-04T09:05:00+05:30", method: "face" }] };
  const denied = await handleBiometricRequest(db, TS, { method: "POST", path: "/punches", headers: { authorization: "Bearer wrong" }, body });
  assert.equal(denied.status, 401);
  const ok = await handleBiometricRequest(db, TS, { method: "POST", path: "/punches", headers: { authorization: "Bearer secret-key" }, body });
  assert.equal(JSON.parse(ok.body).accepted, 1);
  assert.equal(db.data.attendance.s1_stu1.method, "face");
});

// --- QR scans -------------------------------------------------------------------
test("QR scans are checked against server time, signature and section", () => {
  const s = session();
  const ts = Date.parse("2026-11-04T03:31:00Z");
  const code = (over = {}) => JSON.stringify({ sId: "s1", ts, sig: core.qrSignature("s1", ts, "t1"), ...over });
  const student = { role: "student", section: "A" };
  const check = (payload, extra = {}) => core.verifyQrScan({
    scan: { sessionId: "s1", payload }, session: s, student, receivedAtMs: ts + 4000, ...extra,
  });
  assert.deepEqual(check(code()), { ok: true });
  assert.equal(check(code(), { receivedAtMs: ts + 20000 }).reason, "expired", "a forwarded photo goes stale");
  assert.equal(check(code({ sig: "0000000000000000" })).reason, "bad-signature");
  assert.equal(check(code(), { student: { role: "student", section: "B" } }).reason, "wrong-section");
  assert.equal(check(code({ sId: "other" })).reason, "wrong-session");
  assert.equal(check("not json").reason, "unreadable-code");
});

test("an accepted QR scan writes the same record the review screen reads", async () => {
  const db = fakeDb(); seed(db);
  const result = await core.markPresent(db, TS, { sessionId: "s1", session: session(), studentId: "stu1", source: "qr" });
  assert.equal(result, "marked");
  assert.equal(db.data.attendance.s1_stu1.status, "present");
  assert.equal(await core.markPresent(db, TS, { sessionId: "s1", session: session(), studentId: "stu1", source: "biometric" }), "already");
});
