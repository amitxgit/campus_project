// Run with: cd tests && npm ci && npm test
// Needs Java (for the Firestore emulator) and firebase_functions/ deps installed.
// Integration test for the Cloud Functions + firestore.rules, run inside
// `firebase emulators:exec`.
process.env.FIREBASE_AUTH_EMULATOR_HOST ||= "127.0.0.1:9099";
const fs = require("fs");
const crypto = require("crypto");
const assert = require("assert");
const admin = require("firebase-admin");
const {
  initializeTestEnvironment, assertFails, assertSucceeds,
} = require("@firebase/rules-unit-testing");

const PROJECT = process.env.GCLOUD_PROJECT;
admin.initializeApp({ projectId: PROJECT });
const db = admin.firestore();
const FN = `http://127.0.0.1:5001/${PROJECT}/asia-south1`;
const AUTH = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`;

let passed = 0;
async function check(name, fn) {
  try {
    await fn();
    passed++;
    console.log("  ok  ", name);
  } catch (e) {
    console.log("  FAIL", name, "\n       ", e.message);
    process.exitCode = 1;
  }
}

async function call(fnName, data, token) {
  const res = await fetch(`${FN}/${fnName}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify({ data }),
  });
  const body = await res.json();
  if (body.error) {
    const err = new Error(body.error.message);
    err.status = body.error.status;
    throw err;
  }
  return body.result;
}

async function expectError(promise, status) {
  try {
    await promise;
  } catch (e) {
    assert.strictEqual(e.status, status, `expected ${status}, got ${e.status}: ${e.message}`);
    return e;
  }
  throw new Error(`expected ${status}, but call succeeded`);
}

async function signIn(email, password) {
  const res = await fetch(`${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  const body = await res.json();
  if (!body.idToken) throw new Error(`sign-in failed: ${JSON.stringify(body)}`);
  return body.idToken;
}

async function makeUser(uid, profile) {
  await admin.auth().createUser({ uid, email: `${uid}@test.edu`, password: "secret123" });
  await db.collection("users").doc(uid).set({ isActive: true, name: uid, ...profile });
  return signIn(`${uid}@test.edu`, "secret123");
}

const sign = (secret, sId, n) =>
  crypto.createHmac("sha256", secret).update(`${sId}:${n}`).digest("hex").substring(0, 32);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  const tAdmin = await makeUser("admin1", { role: "admin" });
  const tTeacher = await makeUser("teacher1", { role: "teacher" });
  const tTeacher2 = await makeUser("teacher2", { role: "teacher" });
  const tStudent = await makeUser("student1", { role: "student", section: "IV-HE", phone: "111" });
  const tOther = await makeUser("student2", { role: "student", section: "III-HE", phone: "222" });
  await db.collection("timetable").doc("entry1").set({
    subjectId: "sub1", dayOfWeek: "Mon", startTime: "08:30", endTime: "09:30",
    room: "101", section: "IV-HE", teacherIds: ["teacher1"],
  });

  console.log("QR attendance");
  let session;
  await check("teacher not on the entry cannot start a session", () =>
    expectError(call("startAttendanceSession", { entryId: "entry1" }, tTeacher2), "PERMISSION_DENIED"));
  await check("teacher starts session", async () => {
    session = await call("startAttendanceSession", { entryId: "entry1" }, tTeacher);
    assert.ok(session.sessionId && session.secret.length === 64);
    const doc = (await db.collection("attendance_sessions").doc(session.sessionId).get()).data();
    assert.strictEqual(doc.slot, "08:30-09:30");
    assert.strictEqual(doc.teacherId, "teacher1");
  });
  const qr = (n) => ({ sId: session.sessionId, n, sig: sign(session.secret, session.sessionId, n) });

  await check("unauthenticated scan rejected", () =>
    expectError(call("markAttendance", qr(0)), "UNAUTHENTICATED"));
  await check("forged signature rejected", () =>
    expectError(call("markAttendance", { ...qr(0), sig: "0".repeat(32) }, tStudent), "PERMISSION_DENIED"));
  await check("old (screenshotted) code rejected", () =>
    expectError(call("markAttendance", qr(-10), tStudent), "DEADLINE_EXCEEDED"));
  await check("code from the future rejected", () =>
    expectError(call("markAttendance", qr(50), tStudent), "DEADLINE_EXCEEDED"));
  await check("student from another section rejected", () =>
    expectError(call("markAttendance", qr(0), tOther), "PERMISSION_DENIED"));
  await check("teacher cannot mark themselves", () =>
    expectError(call("markAttendance", qr(0), tTeacher), "PERMISSION_DENIED"));
  await check("valid scan records attendance", async () => {
    const r = await call("markAttendance", qr(0), tStudent);
    assert.strictEqual(r.alreadyMarked, false);
    const rec = (await db.collection("attendance").doc(`${session.sessionId}_student1`).get()).data();
    assert.strictEqual(rec.status, "present");
    assert.strictEqual(rec.subjectId, "sub1");
    assert.strictEqual(rec.markedByTeacherId, "teacher1");
  });
  await check("second scan is idempotent", async () => {
    const r = await call("markAttendance", qr(0), tStudent);
    assert.strictEqual(r.alreadyMarked, true);
  });
  await check("closed session rejects scans", async () => {
    await db.collection("attendance_sessions").doc(session.sessionId).update({ isActive: false });
    await expectError(call("markAttendance", qr(0), tStudent), "FAILED_PRECONDITION");
  });

  console.log("User management");
  await check("teacher cannot create accounts", () =>
    expectError(call("createUserAccount", { password: "abcdef", profile: { role: "student", email: "x@t.edu" } }, tTeacher), "PERMISSION_DENIED"));
  await check("admin creates an account that can sign in", async () => {
    const r = await call("createUserAccount", {
      password: "newpass1",
      profile: { role: "student", name: "New Kid", email: "newkid@test.edu", section: "IV-HE", year: 4, bogusField: "x" },
    }, tAdmin);
    await signIn("newkid@test.edu", "newpass1");
    const doc = (await db.collection("users").doc(r.uid).get()).data();
    assert.strictEqual(doc.role, "student");
    assert.strictEqual(doc.bogusField, undefined);
    assert.ok(doc.createdAt);
  });
  await check("duplicate email rejected", () =>
    expectError(call("createUserAccount", { password: "newpass1", profile: { role: "student", email: "newkid@test.edu" } }, tAdmin), "ALREADY_EXISTS"));
  await check("admin deletes login + profile", async () => {
    const u = await admin.auth().getUserByEmail("newkid@test.edu");
    await call("deleteUserAccount", { uid: u.uid }, tAdmin);
    assert.strictEqual((await db.collection("users").doc(u.uid).get()).exists, false);
    await assert.rejects(admin.auth().getUser(u.uid));
  });
  await check("admin cannot delete themselves", () =>
    expectError(call("deleteUserAccount", { uid: "admin1" }, tAdmin), "FAILED_PRECONDITION"));

  console.log("Notifications");
  await check("teacher request fans out to recipients", async () => {
    const ref = await db.collection("notification_requests").add({
      targetUserIds: ["student1", "student2"], title: "Hi", body: "B", type: "remarkSaved",
      requestedBy: "teacher1", status: "pending",
    });
    for (let i = 0; i < 40 && (await ref.get()).data().status === "pending"; i++) await sleep(250);
    assert.strictEqual((await ref.get()).data().status, "sent");
    const n = await db.collection("notifications").where("userId", "==", "student2").get();
    assert.strictEqual(n.size, 1);
    assert.strictEqual(n.docs[0].data().read, false);
  });
  await check("student-originated request is rejected", async () => {
    const ref = await db.collection("notification_requests").add({
      targetUserIds: ["student2"], title: "spam", body: "", type: "general", requestedBy: "student1", status: "pending",
    });
    for (let i = 0; i < 40 && (await ref.get()).data().status === "pending"; i++) await sleep(250);
    assert.strictEqual((await ref.get()).data().status, "rejected");
  });

  console.log("Security rules");
  const env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: { rules: fs.readFileSync(process.argv[2], "utf8"), host: "127.0.0.1", port: 8080 },
    storage: { rules: fs.readFileSync(process.argv[3], "utf8"), host: "127.0.0.1", port: 9199 },
  });
  const as = (uid) => env.authenticatedContext(uid).firestore();
  const student = as("student1");
  const teacher = as("teacher1");
  const sid = session.sessionId;

  await check("student reads own profile", () => assertSucceeds(student.doc("users/student1").get()));
  await check("student reads teacher profile", () => assertSucceeds(student.doc("users/teacher1").get()));
  await check("student cannot read another student", () => assertFails(student.doc("users/student2").get()));
  await check("student teacher-directory query allowed", () =>
    assertSucceeds(student.collection("users").where("role", "==", "teacher").get()));
  await check("student cannot list all users", () => assertFails(student.collection("users").get()));
  await check("student can edit own phone", () => assertSucceeds(student.doc("users/student1").update({ phone: "999" })));
  await check("student cannot promote themselves", () => assertFails(student.doc("users/student1").update({ role: "admin" })));
  await check("student cannot set isAdmin", () => assertFails(student.doc("users/student1").update({ isAdmin: true })));
  await check("student reads own attendance", () =>
    assertSucceeds(student.collection("attendance").where("studentId", "==", "student1").get()));
  await check("student cannot read others' attendance", () =>
    assertFails(student.collection("attendance").where("studentId", "==", "student2").get()));
  await check("student cannot write attendance directly", () =>
    assertFails(student.doc("attendance/fake").set({ studentId: "student1", status: "present", markedByTeacherId: "teacher1" })));
  await check("nobody can read the QR secret", async () => {
    await assertFails(student.doc(`attendance_sessions/${sid}/private/key`).get());
    await assertFails(teacher.doc(`attendance_sessions/${sid}/private/key`).get());
  });
  await check("teacher can close own session", () => assertSucceeds(teacher.doc(`attendance_sessions/${sid}`).update({ isActive: false })));
  await check("teacher cannot change session section", () => assertFails(teacher.doc(`attendance_sessions/${sid}`).update({ section: "X" })));
  await check("teacher saves reviewed attendance", () =>
    assertSucceeds(teacher.doc(`attendance/${sid}_student2`).set({ studentId: "student2", status: "absent", markedByTeacherId: "teacher1" })));
  await check("teacher cannot attribute marks to another teacher", () =>
    assertFails(teacher.doc(`attendance/${sid}_x`).set({ studentId: "x", status: "present", markedByTeacherId: "teacher2" })));
  await check("student cannot write notifications", () =>
    assertFails(student.collection("notifications").add({ userId: "student2", title: "x" })));
  await check("student marks own notification read", async () => {
    const n = await db.collection("notifications").where("userId", "==", "student1").limit(1).get();
    await assertSucceeds(student.doc(`notifications/${n.docs[0].id}`).update({ read: true }));
  });
  await check("student cannot queue notifications", () =>
    assertFails(student.collection("notification_requests").add({ requestedBy: "student1", targetUserIds: ["student2"] })));
  await check("student raises a query", () =>
    assertSucceeds(student.doc("queries/q1").set({ raisedByStudentId: "student1", status: "open", title: "t" })));
  await check("student cannot raise query as someone else", () =>
    assertFails(student.doc("queries/q2").set({ raisedByStudentId: "student2", status: "open" })));
  await check("student cannot change timetable", () => assertFails(student.doc("timetable/entry1").update({ room: "x" })));
  await check("deactivated user loses access", async () => {
    await db.doc("users/student2").update({ isActive: false });
    await assertFails(as("student2").doc("timetable/entry1").get());
  });

  console.log("Notices, assignments, profile");
  const { Timestamp } = require("firebase-admin/firestore");
  const now = Timestamp.now();
  await db.doc("notices/n_all").set({ title: "A", targetAudience: "all", authorId: "admin1", createdAt: now });
  await db.doc("notices/n_teach").set({ title: "T", targetAudience: "teachers", authorId: "admin1", createdAt: now });
  await db.doc("assignments/a_mine").set({ title: "HW", section: "IV-HE", teacherId: "teacher1", subjectId: "sub1", dueDate: now, createdAt: now });
  await db.doc("assignments/a_other").set({ title: "HW2", section: "III-HE", teacherId: "teacher1", subjectId: "sub2", dueDate: now, createdAt: now });
  const teacher2 = as("teacher2");

  await check("student notice query (all + students) allowed", () =>
    assertSucceeds(student.collection("notices").where("targetAudience", "in", ["all", "students"]).orderBy("createdAt", "desc").get()));
  await check("student cannot list teacher-only notices", () => assertFails(student.collection("notices").get()));
  await check("student cannot read a teachers-only notice", () => assertFails(student.doc("notices/n_teach").get()));
  await check("teacher lists all notices", () => assertSucceeds(teacher.collection("notices").orderBy("createdAt", "desc").get()));
  await check("teacher posts notice as self", () =>
    assertSucceeds(teacher.doc("notices/n_new").set({ title: "x", targetAudience: "students", authorId: "teacher1", createdAt: new Date() })));
  await check("teacher cannot post as someone else", () =>
    assertFails(teacher.doc("notices/n_fake").set({ title: "x", targetAudience: "all", authorId: "admin1", createdAt: new Date() })));
  await check("student cannot post notices", () =>
    assertFails(student.doc("notices/n_s").set({ title: "x", targetAudience: "all", authorId: "student1", createdAt: new Date() })));
  await check("teacher cannot delete another's notice", () => assertFails(teacher2.doc("notices/n_new").delete()));
  await check("author deletes own notice", () => assertSucceeds(teacher.doc("notices/n_new").delete()));

  await check("student lists own-section assignments", () =>
    assertSucceeds(student.collection("assignments").where("section", "==", "IV-HE").orderBy("dueDate", "desc").get()));
  await check("student cannot list another section's assignments", () =>
    assertFails(student.collection("assignments").where("section", "==", "III-HE").get()));
  await check("teacher creates assignment as self", () =>
    assertSucceeds(teacher.doc("assignments/a_new").set({ title: "x", section: "IV-HE", teacherId: "teacher1", dueDate: new Date() })));
  await check("teacher cannot delete another teacher's assignment", () => assertFails(teacher2.doc("assignments/a_mine").delete()));
  await check("student cannot create assignments", () =>
    assertFails(student.doc("assignments/a_s").set({ title: "x", section: "IV-HE", teacherId: "student1" })));
  await check("student turns in own work", () =>
    assertSucceeds(student.doc("assignments/a_mine/submissions/student1").set({ studentId: "student1", text: "done", submittedAt: new Date() })));
  await check("student can resubmit", () =>
    assertSucceeds(student.doc("assignments/a_mine/submissions/student1").set({ studentId: "student1", text: "v2", submittedAt: new Date() })));
  await check("student cannot submit for someone else", () =>
    assertFails(student.doc("assignments/a_mine/submissions/student9").set({ studentId: "student9", text: "x" })));
  await check("student cannot submit to another section", () =>
    assertFails(student.doc("assignments/a_other/submissions/student1").set({ studentId: "student1", text: "x" })));
  await check("teacher lists submissions", () => assertSucceeds(teacher.collection("assignments/a_mine/submissions").get()));
  await check("student cannot list others' submissions", () => assertFails(student.collection("assignments/a_mine/submissions").get()));
  await check("student edits own bio", () => assertSucceeds(student.doc("users/student1").update({ bio: "hello", phone: "123" })));

  console.log("Storage");
  const file = new Uint8Array([1, 2, 3]);
  const sStore = env.authenticatedContext("student1").storage();
  await check("student uploads into own folder", () =>
    assertSucceeds(sStore.ref("submissions/a_mine/student1/hw.pdf").put(file)));
  await check("student cannot upload into another's folder", () =>
    assertFails(sStore.ref("submissions/a_mine/student2/hw.pdf").put(file)));
  await check("files over 20 MB rejected", () =>
    assertFails(sStore.ref("submissions/a_mine/student1/big.bin").put(new Uint8Array(21 * 1024 * 1024))));
  await check("teacher downloads student file", () =>
    assertSucceeds(env.authenticatedContext("teacher1").storage().ref("submissions/a_mine/student1/hw.pdf").getMetadata()));
  await check("another student cannot download it", () =>
    assertFails(env.authenticatedContext("student2").storage().ref("submissions/a_mine/student1/hw.pdf").getMetadata()));

  console.log("Institute settings");
  const adminDb = as("admin1");
  await check("anyone (even signed out) can read settings", () =>
    assertSucceeds(env.unauthenticatedContext().firestore().doc("settings/institution").get()));
  await check("admin saves settings", () =>
    assertSucceeds(adminDb.doc("settings/institution").set({ name: "Apex Classes", type: "coaching", groups: ["IV-HE"] })));
  await check("teacher cannot change settings", () => assertFails(teacher.doc("settings/institution").update({ name: "X" })));
  await check("admin sets the UPI ID students pay to", () =>
    assertSucceeds(adminDb.doc("settings/institution").update({ upiId: "apex@okhdfcbank", upiPayeeName: "Apex Classes" })));
  await check("students and teachers cannot redirect payments to their own UPI ID", async () => {
    await assertFails(student.doc("settings/institution").update({ upiId: "thief@ybl" }));
    await assertFails(teacher.doc("settings/institution").update({ upiId: "thief@ybl" }));
  });

  console.log("Fees");
  await check("admin creates fee plan", () =>
    assertSucceeds(adminDb.doc("fee_accounts/student1").set({ studentName: "student1", totalFee: 30000, discount: 0, instalments: [], paidAmount: 0 })));
  await check("admin records payment with receipt counter (transaction)", () =>
    assertSucceeds(adminDb.runTransaction(async (tx) => {
      const c = await tx.get(adminDb.doc("meta/counters"));
      const next = ((c.exists && c.data().receiptSeq) || 0) + 1;
      tx.set(adminDb.doc("meta/counters"), { receiptSeq: next }, { merge: true });
      tx.set(adminDb.doc("fee_accounts/student1/payments/p1"), { amount: 5000, receiptNo: next, voided: false });
      tx.update(adminDb.doc("fee_accounts/student1"), { paidAmount: 5000 });
    })));
  await check("student reads own fees and receipts", async () => {
    await assertSucceeds(student.doc("fee_accounts/student1").get());
    await assertSucceeds(student.collection("fee_accounts/student1/payments").get());
  });
  await check("student cannot edit own fees", () => assertFails(student.doc("fee_accounts/student1").update({ paidAmount: 30000 })));
  await check("student cannot add a payment", () =>
    assertFails(student.doc("fee_accounts/student1/payments/fake").set({ amount: 99999 })));
  await check("student cannot read another's fees", () => assertFails(as("student2").doc("fee_accounts/student1").get()));
  await check("teacher cannot see fees", () => assertFails(teacher.doc("fee_accounts/student1").get()));
  await check("students cannot touch receipt counter", () => assertFails(student.doc("meta/counters").get()));
  await check("admin reads every payment in a date range (fee ledger)", async () => {
    await db.doc("fee_accounts/student1/payments/p_led").set({ amount: 1200, receiptNo: 99, voided: false, paidOn: new Date("2026-11-02T06:00:00Z") });
    const snap = await assertSucceeds(adminDb.collectionGroup("payments")
      .where("paidOn", ">=", new Date("2026-11-01T00:00:00Z")).where("paidOn", "<", new Date("2026-12-01T00:00:00Z"))
      .orderBy("paidOn").get());
    assert.deepStrictEqual(snap.docs.map((d) => d.ref.parent.parent.id), ["student1"]);
  });
  await check("students and teachers cannot list everyone's payments", async () => {
    await assertFails(student.collectionGroup("payments").get());
    await assertFails(teacher.collectionGroup("payments").get());
  });
  await check("admin reads attendance for a date range; teachers cannot list all", async () => {
    const range = (c) => c.collection("attendance").where("date", ">=", new Date("2026-11-01")).where("date", "<", new Date("2026-12-01")).get();
    await assertSucceeds(range(adminDb));
    await assertFails(range(student));
  });

  console.log("Tests & results");
  await check("teacher creates a test as self", () =>
    assertSucceeds(teacher.doc("tests/t1").set({ name: "WT1", section: "IV-HE", maxMarks: 100, createdBy: "teacher1" })));
  await check("teacher enters marks", () => assertSucceeds(teacher.doc("tests/t1/marks/all").set({ scores: { student1: 80 }, absent: [] })));
  await check("teacher publishes a result", () =>
    assertSucceeds(teacher.doc("student_results/student1").set({ results: { t1: { marks: 80, rank: 1 } } }, { merge: true })));
  await check("student reads own results", () => assertSucceeds(student.doc("student_results/student1").get()));
  await check("student cannot read raw marks or tests", async () => {
    await assertFails(student.doc("tests/t1/marks/all").get());
    await assertFails(student.doc("tests/t1").get());
  });
  await check("student cannot read another's results", () => assertFails(as("student2").doc("student_results/student1").get()));
  await check("student cannot write results", () => assertFails(student.doc("student_results/student1").set({ results: {} })));

  console.log("Enquiries");
  const enq = (by, extra = {}) => ({
    name: "Riya", phone: "9000011111", parentPhone: "9811122233", course: "Class 11 JEE", batch: "",
    source: "walkIn", status: "new", nextFollowUp: null, notes: "", createdBy: by,
    createdAt: new Date(), updatedAt: new Date(), ...extra,
  });
  await check("teacher adds an enquiry as themselves", () =>
    assertSucceeds(teacher.doc("enquiries/e_t1").set(enq("teacher1"))));
  await check("teacher cannot add one as someone else, or already joined/linked", async () => {
    await assertFails(teacher.doc("enquiries/e_t2").set(enq("admin1")));
    await assertFails(teacher.doc("enquiries/e_t3").set(enq("teacher1", { status: "joined" })));
    await assertFails(teacher.doc("enquiries/e_t4").set(enq("teacher1", { studentId: "student1" })));
    await assertFails(teacher.doc("enquiries/e_t5").set(enq("teacher1", { name: "" })));
  });
  await check("teacher cannot read, list, change or delete enquiries", async () => {
    await assertFails(teacher.doc("enquiries/e_t1").get());
    await assertFails(teacher.collection("enquiries").get());
    await assertFails(teacher.doc("enquiries/e_t1").update({ status: "lost" }));
    await assertFails(teacher.doc("enquiries/e_t1").delete());
  });
  await check("students cannot add or read enquiries", async () => {
    await assertFails(student.doc("enquiries/e_s1").set(enq("student1")));
    await assertFails(student.doc("enquiries/e_t1").get());
  });
  await check("admin lists this month's enquiries, newest first", () =>
    assertSucceeds(adminDb.collection("enquiries")
      .where("createdAt", ">=", new Date(new Date().getFullYear(), new Date().getMonth(), 1)).get()));
  await check("admin follows up, converts and deletes", async () => {
    await assertSucceeds(adminDb.collection("enquiries").orderBy("createdAt", "desc").get());
    await assertSucceeds(adminDb.doc("enquiries/e_t1").update({ status: "demoBooked", nextFollowUp: new Date() }));
    await assertSucceeds(adminDb.doc("enquiries/e_t1").update({ status: "joined", studentId: "student1", nextFollowUp: null }));
    await assertSucceeds(adminDb.doc("enquiries/e_a1").set(enq("admin1", { status: "contacted" })));
    await assertSucceeds(adminDb.doc("enquiries/e_a1").delete());
  });

  console.log("Parent alerts");
  // A stand-in for the WhatsApp Cloud API that records what it was sent.
  const http = require("http");
  const received = [];
  const mock = http.createServer((req, res) => {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      received.push({ url: req.url, auth: req.headers.authorization, body: JSON.parse(body) });
      const fail = req.url.includes("/BADID/");
      res.writeHead(fail ? 400 : 200, { "Content-Type": "application/json" });
      res.end(JSON.stringify(fail ? { error: { message: "Invalid phone number id" } } : { messages: [{ id: "wamid.1" }] }));
    });
  });
  await new Promise((r) => mock.listen(0, "127.0.0.1", r));
  const mockBase = `http://127.0.0.1:${mock.address().port}`;
  const waitStatus = async (ref) => {
    for (let i = 0; i < 40; i++) {
      const st = (await ref.get()).data().status;
      if (st !== "pending") return st;
      await sleep(250);
    }
    return "pending";
  };
  const queue = (data) => db.collection("parent_alerts").add({ status: "pending", createdAt: new Date(), ...data });
  await db.doc("users/student1").update({ parentPhone: "98123 45678", name: "Asha" });

  await check("alert without WhatsApp configured is marked notConfigured", async () => {
    const ref = await queue({ studentId: "student1", kind: "feeReminder", params: ["a", "b", "c", "d", "e"], requestedBy: "admin1" });
    assert.strictEqual(await waitStatus(ref), "notConfigured");
  });
  await check("students cannot read or write WhatsApp secrets", async () => {
    await assertFails(student.doc("secrets/whatsapp").set({ token: "x" }));
    await assertFails(adminDb.doc("secrets/whatsapp").get());
  });
  await check("admin saves WhatsApp credentials (write-only)", () =>
    assertSucceeds(adminDb.doc("secrets/whatsapp").set({ phoneNumberId: "PNID", token: "tok123", apiBase: mockBase })));
  await check("queued alert is sent as the right template to the parent", async () => {
    const ref = await queue({ studentId: "student1", kind: "testResult", params: ["Asha", "80/100", "WT1", "Apex"], requestedBy: "teacher1" });
    assert.strictEqual(await waitStatus(ref), "sent");
    const msg = received[received.length - 1];
    assert.strictEqual(msg.url, "/PNID/messages");
    assert.strictEqual(msg.auth, "Bearer tok123");
    assert.strictEqual(msg.body.to, "919812345678");
    assert.strictEqual(msg.body.template.name, "test_result");
    assert.deepStrictEqual(msg.body.template.components[0].parameters.map((p) => p.text), ["Asha", "80/100", "WT1", "Apex"]);
  });
  await check("fee reminder goes out with its pay link as the 5th value", async () => {
    const link = "https://batchwise-2bd30.web.app/pay.html?pa=apex@ybl&pn=Apex&am=5000.00&cu=INR&tn=Fees%20Asha";
    const values = ["₹5,000", "Asha", "10 Jan 2026", "Apex", link];
    const ref = await queue({ studentId: "student1", kind: "feeReminder", params: values, requestedBy: "admin1" });
    assert.strictEqual(await waitStatus(ref), "sent");
    const msg = received[received.length - 1];
    assert.strictEqual(msg.body.template.name, "fee_reminder");
    assert.deepStrictEqual(msg.body.template.components[0].parameters.map((p) => p.text), values);
  });
  await check("old 4-value fee reminder and receipt are rejected", async () => {
    for (const kind of ["feeReminder", "feeReceipt"]) {
      const ref = await queue({ studentId: "student1", kind, params: ["a", "b", "c", "d"], requestedBy: "admin1" });
      assert.strictEqual(await waitStatus(ref), "rejected", kind);
    }
  });
  await check("student without a parent number is marked noPhone", async () => {
    const ref = await queue({ studentId: "student2", kind: "absence", params: ["x", "y", "z"], requestedBy: "teacher1" });
    assert.strictEqual(await waitStatus(ref), "noPhone");
  });
  await check("wrong number of template values is rejected", async () => {
    const ref = await queue({ studentId: "student1", kind: "absence", params: ["only one"], requestedBy: "teacher1" });
    assert.strictEqual(await waitStatus(ref), "rejected");
  });
  await check("alert queued as a student is rejected by the function", async () => {
    const ref = await queue({ studentId: "student1", kind: "absence", params: ["a", "b", "c"], requestedBy: "student1" });
    assert.strictEqual(await waitStatus(ref), "rejected");
  });
  await check("WhatsApp API errors are recorded as failed", async () => {
    await db.doc("secrets/whatsapp").update({ phoneNumberId: "BADID" });
    const ref = await queue({ studentId: "student1", kind: "absence", params: ["a", "b", "c"], requestedBy: "teacher1" });
    assert.strictEqual(await waitStatus(ref), "failed");
    assert.match((await ref.get()).data().error, /Invalid phone number id/);
    await db.doc("secrets/whatsapp").update({ phoneNumberId: "PNID" });
  });
  await check("staff can queue alerts but students cannot", async () => {
    const ok = { studentId: "student1", kind: "absence", params: ["a", "b", "c"], status: "pending" };
    await assertSucceeds(teacher.collection("parent_alerts").add({ ...ok, requestedBy: "teacher1" }));
    await assertFails(student.collection("parent_alerts").add({ ...ok, requestedBy: "student1" }));
    await assertFails(teacher.collection("parent_alerts").add({ ...ok, requestedBy: "system" }));
  });
  await check("automatic absence alert: once per student per day", async () => {
    await db.doc("settings/institution").set({ name: "Apex", parentAlertsEnabled: true, autoAbsenceAlerts: true, whatsappSender: "+91..." });
    const before = received.length;
    const day = new Date("2026-11-03T05:00:00Z");
    await db.doc("attendance/s1_student1").set({ studentId: "student1", status: "absent", date: day });
    await db.doc("attendance/s2_student1").set({ studentId: "student1", status: "absent", date: day });
    await sleep(4000);
    const alerts = await db.collection("parent_alerts").where("kind", "==", "absence").where("requestedBy", "==", "system").get();
    assert.strictEqual(alerts.size, 1);
    assert.strictEqual(alerts.docs[0].id, "absence_student1_2026-11-03");
    assert.deepStrictEqual(alerts.docs[0].data().params, ["Asha", "3 Nov 2026", "Apex"]);
    const sentForDay = received.slice(before).filter((m) =>
      m.body.template.name === "absence_alert" && m.body.template.components[0].parameters[1].text === "3 Nov 2026");
    assert.strictEqual(sentForDay.length, 1);
  });
  await check("no automatic alert when the setting is off", async () => {
    await db.doc("settings/institution").update({ autoAbsenceAlerts: false });
    await db.doc("attendance/s3_student1").set({ studentId: "student1", status: "absent", date: new Date("2026-11-04T05:00:00Z") });
    await sleep(3000);
    assert.strictEqual((await db.doc("parent_alerts/absence_student1_2026-11-04").get()).exists, false);
  });
  await check("WhatsApp test send works for admins only", async () => {
    await expectError(call("testWhatsApp", { to: "9812345678" }, tTeacher), "PERMISSION_DENIED");
    await call("testWhatsApp", { to: "9812345678" }, tAdmin);
    assert.strictEqual(received[received.length - 1].body.template.name, "hello_world");
  });
  mock.close();

  console.log("Razorpay payment links");
  // A stand-in for the Razorpay API that records what it was sent.
  const rzpCalls = [];
  const rzpMock = http.createServer((req, res) => {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      const parsed = JSON.parse(body);
      rzpCalls.push({ url: req.url, auth: req.headers.authorization, body: parsed });
      const id = `plink_${rzpCalls.length}`;
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ id, short_url: `https://rzp.io/rzp/${id}`, amount: parsed.amount }));
    });
  });
  await new Promise((r) => rzpMock.listen(0, "127.0.0.1", r));
  const rzpBase = `http://127.0.0.1:${rzpMock.address().port}`;
  const WEBHOOK_SECRET = "whsec_test";
  const webhook = async (event, secret = WEBHOOK_SECRET) => {
    const raw = JSON.stringify(event);
    const sig = crypto.createHmac("sha256", secret).update(raw).digest("hex");
    const res = await fetch(`${FN}/razorpayWebhook`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Razorpay-Signature": sig },
      body: raw,
    });
    return { status: res.status, text: await res.text() };
  };
  const paidEvent = (linkId, paymentId, paise, method = "upi") => ({
    event: "payment_link.paid",
    payload: {
      payment_link: { entity: { id: linkId, status: "paid", amount: paise, amount_paid: paise } },
      payment: { entity: { id: paymentId, amount: paise, method, status: "captured", created_at: 1793000000 } },
    },
  });
  await db.doc("fee_accounts/student1").set({
    studentName: "Asha", totalFee: 30000, discount: 0, paidAmount: 5000,
    instalments: [
      { label: "Instalment 1", amount: 10000, dueDate: new Date("2026-01-10T00:00:00+05:30") },
      { label: "Instalment 2", amount: 20000, dueDate: new Date("2099-01-10T00:00:00+05:30") },
    ],
  });

  await check("payment link needs Razorpay connected", () =>
    expectError(call("createFeePaymentLink", { studentId: "student1" }, tAdmin), "FAILED_PRECONDITION"));
  await check("Razorpay keys are write-only and admin-only", async () => {
    await assertFails(student.doc("secrets/razorpay").set({ keyId: "rzp_x" }));
    await assertFails(teacher.doc("secrets/razorpay").set({ keyId: "rzp_x" }));
    await assertSucceeds(adminDb.doc("secrets/razorpay").set({ keyId: "rzp_test_1", keySecret: "ks", webhookSecret: WEBHOOK_SECRET }));
    await assertFails(adminDb.doc("secrets/razorpay").get());
    await db.doc("secrets/razorpay").update({ apiBase: rzpBase });
  });
  await check("only admins can create payment links", () =>
    expectError(call("createFeePaymentLink", { studentId: "student1" }, tTeacher), "PERMISSION_DENIED"));
  let link;
  await check("payment link defaults to what's due now (the overdue part)", async () => {
    link = await call("createFeePaymentLink", { studentId: "student1" }, tAdmin);
    assert.strictEqual(link.amount, 5000);
    assert.strictEqual(link.url, `https://rzp.io/rzp/${link.id}`);
    const sent = rzpCalls[rzpCalls.length - 1];
    assert.strictEqual(sent.url, "/v1/payment_links");
    assert.strictEqual(sent.auth, `Basic ${Buffer.from("rzp_test_1:ks").toString("base64")}`);
    assert.strictEqual(sent.body.amount, 500000);
    assert.strictEqual(sent.body.currency, "INR");
    assert.strictEqual(sent.body.customer.contact, "+919812345678");
    assert.deepStrictEqual(sent.body.notes, { studentId: "student1" });
    const saved = (await db.doc(`payment_links/${link.id}`).get()).data();
    assert.strictEqual(saved.studentId, "student1");
    assert.strictEqual(saved.status, "created");
  });
  await check("payment link amount can't exceed the balance", async () => {
    await expectError(call("createFeePaymentLink", { studentId: "student1", amount: 25001 }, tAdmin), "INVALID_ARGUMENT");
    await expectError(call("createFeePaymentLink", { studentId: "student1", amount: 0 }, tAdmin), "INVALID_ARGUMENT");
    await expectError(call("createFeePaymentLink", { studentId: "student2" }, tAdmin), "FAILED_PRECONDITION");
  });
  await check("only admins can read payment links; nobody writes them", async () => {
    await assertSucceeds(adminDb.doc(`payment_links/${link.id}`).get());
    await assertFails(student.doc(`payment_links/${link.id}`).get());
    await assertFails(adminDb.doc(`payment_links/${link.id}`).update({ status: "paid" }));
  });
  await check("webhook with a bad signature is rejected and records nothing", async () => {
    const res = await webhook(paidEvent(link.id, "pay_FORGED", 500000), "wrong-secret");
    assert.strictEqual(res.status, 400);
    assert.strictEqual((await db.doc("fee_accounts/student1/payments/pay_FORGED").get()).exists, false);
    assert.strictEqual((await db.doc("fee_accounts/student1").get()).data().paidAmount, 5000);
  });
  await check("signed payment_link.paid records the payment with the next receipt number", async () => {
    const before = (await db.doc("meta/counters").get()).data().receiptSeq;
    const res = await webhook(paidEvent(link.id, "pay_ABC", 500000, "netbanking"));
    assert.strictEqual(res.status, 200);
    assert.strictEqual(res.text, "recorded");
    const pay = (await db.doc("fee_accounts/student1/payments/pay_ABC").get()).data();
    assert.strictEqual(pay.amount, 5000);
    assert.strictEqual(pay.mode, "bankTransfer");
    assert.strictEqual(pay.reference, "pay_ABC");
    assert.strictEqual(pay.receiptNo, before + 1);
    assert.strictEqual(pay.voided, false);
    assert.strictEqual((await db.doc("meta/counters").get()).data().receiptSeq, before + 1);
    assert.strictEqual((await db.doc("fee_accounts/student1").get()).data().paidAmount, 10000);
    const saved = (await db.doc(`payment_links/${link.id}`).get()).data();
    assert.strictEqual(saved.status, "paid");
    assert.strictEqual(saved.paymentId, "pay_ABC");
  });
  await check("a repeated webhook does not record the payment twice", async () => {
    const res = await webhook(paidEvent(link.id, "pay_ABC", 500000, "netbanking"));
    assert.strictEqual(res.status, 200);
    assert.strictEqual(res.text, "duplicate");
    const pays = await db.collection("fee_accounts/student1/payments").where("reference", "==", "pay_ABC").get();
    assert.strictEqual(pays.size, 1);
    assert.strictEqual((await db.doc("fee_accounts/student1").get()).data().paidAmount, 10000);
  });
  await check("concurrent duplicate deliveries still record once", async () => {
    const l2 = await call("createFeePaymentLink", { studentId: "student1", amount: 1000 }, tAdmin);
    const results = await Promise.all([1, 2, 3].map(() => webhook(paidEvent(l2.id, "pay_RACE", 100000, "wallet"))));
    assert.deepStrictEqual(results.map((r) => r.status), [200, 200, 200]);
    assert.strictEqual(results.filter((r) => r.text === "recorded").length, 1);
    assert.strictEqual((await db.doc("fee_accounts/student1/payments/pay_RACE").get()).data().mode, "online");
    assert.strictEqual((await db.doc("fee_accounts/student1").get()).data().paidAmount, 11000);
  });
  await check("payments for links the app didn't create are ignored", async () => {
    const res = await webhook(paidEvent("plink_STRANGER", "pay_X", 999900));
    assert.strictEqual(res.status, 200);
    assert.strictEqual(res.text, "unknown link");
    assert.strictEqual((await db.doc("fee_accounts/student1").get()).data().paidAmount, 11000);
  });
  await check("other webhook events are acknowledged and ignored", async () => {
    const res = await webhook({ event: "payment.failed", payload: {} });
    assert.strictEqual(res.status, 200);
    assert.strictEqual(res.text, "ignored");
  });
  rzpMock.close();

  console.log("Bulk import & mobile sign-in");
  let imported;
  await check("teacher cannot bulk import", () =>
    expectError(call("bulkCreateStudents", { rows: [{ name: "x", section: "A", phone: "9000000001" }] }, tTeacher), "PERMISSION_DENIED"));
  await check("admin imports mixed rows; bad rows reported, good rows created", async () => {
    const res = await call("bulkCreateStudents", { rows: [
      { name: "Phone Kid", section: "IV-HE", phone: "+91 90000 00001", parentPhone: "9811111111", rollNo: "7" },
      { name: "Email Kid", section: "IV-HE", email: "Email.Kid@test.edu", password: "chosen1" },
      { name: "", section: "IV-HE", phone: "9000000002" },
      { name: "Dup", section: "IV-HE", email: "email.kid@test.edu" },
    ] }, tAdmin);
    imported = res.results;
    assert.deepStrictEqual(imported.map((r) => r.ok), [true, true, false, false]);
    assert.strictEqual(imported[0].login, "9000000001@students.batchwise.app");
    assert.strictEqual(imported[0].password.length, 8);
    assert.strictEqual(imported[1].password, null);
    const doc = (await db.doc(`users/${imported[0].uid}`).get()).data();
    assert.strictEqual(doc.role, "student");
    assert.strictEqual(doc.section, "IV-HE");
    assert.strictEqual(doc.parentPhone, "9811111111");
  });
  await check("imported students can sign in (mobile and email)", async () => {
    await signIn("9000000001@students.batchwise.app", imported[0].password);
    await signIn("email.kid@test.edu", "chosen1");
  });
  await check("admin sets a new password for a mobile-login student", async () => {
    await call("setUserPassword", { uid: imported[0].uid, password: "newpass9" }, tAdmin);
    await signIn("9000000001@students.batchwise.app", "newpass9");
    await expectError(call("setUserPassword", { uid: imported[0].uid, password: "x" }, tAdmin), "INVALID_ARGUMENT");
    await expectError(call("setUserPassword", { uid: imported[0].uid, password: "hacked1" }, tTeacher), "PERMISSION_DENIED");
  });

  console.log("Account deletion requests");
  await makeUser("leaver", { role: "student", section: "IV-HE", name: "Leaver" });
  const leaver = as("leaver");
  const ask = { userId: "leaver", name: "Leaver", role: "student", contact: "leaver@test.edu", reason: "Moving city", status: "pending", createdAt: new Date() };
  await check("a user can ask for their own account to be deleted, not someone else's", async () => {
    await assertFails(leaver.doc("deletion_requests/student1").set({ ...ask, userId: "student1" }));
    await assertFails(leaver.doc("deletion_requests/leaver").set({ ...ask, status: "done" }));
    await assertFails(leaver.doc("deletion_requests/leaver").set({ ...ask, handledBy: "me" }));
    await assertSucceeds(leaver.doc("deletion_requests/leaver").set(ask));
    await assertSucceeds(leaver.doc("deletion_requests/leaver").get());
  });
  await check("others can't see it; the user can't mark it done; admins list it", async () => {
    await assertFails(student.doc("deletion_requests/leaver").get());
    await assertFails(teacher.collection("deletion_requests").get());
    await assertFails(leaver.doc("deletion_requests/leaver").update({ status: "done" }));
    await assertSucceeds(adminDb.collection("deletion_requests").where("status", "==", "pending").get());
  });
  await check("cancel while pending; ask again after a decline", async () => {
    await assertSucceeds(leaver.doc("deletion_requests/leaver").delete());
    await assertSucceeds(leaver.doc("deletion_requests/leaver").set(ask));
    await assertSucceeds(adminDb.doc("deletion_requests/leaver").update({ status: "rejected", handledBy: "admin1" }));
    await assertFails(leaver.doc("deletion_requests/leaver").delete());
    await assertSucceeds(leaver.doc("deletion_requests/leaver").update({ ...ask }));
  });
  await check("deleting the account removes notifications, tokens and uploads, and closes the request", async () => {
    await db.collection("notifications").add({ userId: "leaver", title: "x", body: "y", read: false, createdAt: new Date() });
    await db.doc("userTokens/leaver/tokens/tok1").set({ token: "tok1" });
    await db.doc("assignments/a_mine/submissions/leaver").set({ studentId: "leaver", filePath: "submissions/a_mine/leaver/hw.pdf" });
    // The default bucket the functions use (the test library defaults to gs://<project>).
    const fnBucket = `gs://${PROJECT}.appspot.com`;
    await env.authenticatedContext("leaver").storage(fnBucket).ref("submissions/a_mine/leaver/hw.pdf").put(new Uint8Array([1, 2, 3]));
    await env.authenticatedContext("student1").storage(fnBucket).ref("submissions/a_mine/student1/keep.pdf").put(new Uint8Array([1]));

    await call("deleteUserAccount", { uid: "leaver" }, tAdmin);

    assert.strictEqual((await db.doc("users/leaver").get()).exists, false);
    assert.strictEqual((await db.collection("notifications").where("userId", "==", "leaver").get()).size, 0);
    assert.strictEqual((await db.collection("userTokens/leaver/tokens").get()).size, 0);
    assert.strictEqual((await db.doc("assignments/a_mine/submissions/leaver").get()).exists, false);
    const gone = await env.authenticatedContext("teacher1").storage(fnBucket).ref("submissions/a_mine/leaver/hw.pdf")
      .getMetadata().then(() => false, (e) => e.code === "storage/object-not-found");
    assert.ok(gone, "upload still there");
    const req = (await db.doc("deletion_requests/leaver").get()).data();
    assert.strictEqual(req.status, "done");
    assert.strictEqual(req.handledBy, "admin1");
    // Other students' files are untouched.
    await assertSucceeds(env.authenticatedContext("teacher1").storage(fnBucket).ref("submissions/a_mine/student1/keep.pdf").getMetadata());
  });

  console.log("Owner's daily summary");
  // A clean slate for the figures, on a day no other check uses.
  await db.recursiveDelete(db.collection("fee_accounts"));
  await db.recursiveDelete(db.collection("enquiries"));
  const ist = (s) => new Date(`${s}+05:30`);
  await db.doc("fee_accounts/sumA").set({
    studentName: "A", totalFee: 20000, discount: 0, paidAmount: 4000,
    instalments: [
      { label: "I1", amount: 10000, dueDate: ist("2026-11-01T00:00:00") }, // 6000 overdue
      { label: "I2", amount: 10000, dueDate: ist("2026-11-20T00:00:00") }, // due today: not overdue yet
    ],
  });
  await db.doc("fee_accounts/sumB").set({
    studentName: "B", totalFee: 5000, discount: 0, paidAmount: 5000,
    instalments: [{ label: "I1", amount: 5000, dueDate: ist("2026-10-01T00:00:00") }],
  });
  const payAt = (id, amount, at, voided = false) =>
    db.doc(`fee_accounts/sumA/payments/${id}`).set({ amount, paidOn: ist(at), voided, receiptNo: 1 });
  await payAt("x1", 4000, "2026-11-20T10:00:00");
  await payAt("x2", 999, "2026-11-20T11:00:00", true); // void
  await payAt("x3", 700, "2026-11-19T23:00:00"); // yesterday (IST)
  await payAt("x4", 500, "2026-11-20T23:30:00"); // late tonight, still today
  await payAt("x5", 300, "2026-11-21T00:10:00"); // tomorrow
  const mark = (id, studentId, status, at) =>
    db.doc(`attendance/${id}`).set({ studentId, status, date: ist(at), subjectId: "phy", sessionId: "s" });
  await mark("d1", "student1", "absent", "2026-11-20T09:00:00");
  await mark("d2", "student1", "absent", "2026-11-20T11:00:00"); // same student twice
  await mark("d3", "student2", "absent", "2026-11-20T09:00:00");
  await mark("d4", "student3", "present", "2026-11-20T09:00:00");
  await mark("d5", "student3", "absent", "2026-11-21T01:00:00"); // tomorrow
  const enquiryAt = (id, data) => db.doc(`enquiries/${id}`).set({ name: id, createdBy: "admin1", ...data });
  await enquiryAt("n1", { status: "new", createdAt: ist("2026-11-20T10:00:00"), updatedAt: ist("2026-11-20T10:00:00") });
  await enquiryAt("n2", { status: "new", createdAt: ist("2026-11-20T18:00:00"), updatedAt: ist("2026-11-20T18:00:00") });
  await enquiryAt("missed", { status: "contacted", createdAt: ist("2026-11-10T10:00:00"),
    nextFollowUp: ist("2026-11-19T00:00:00"), updatedAt: ist("2026-11-15T10:00:00") });
  await enquiryAt("done", { status: "demoBooked", createdAt: ist("2026-11-10T10:00:00"),
    nextFollowUp: ist("2026-11-20T00:00:00"), updatedAt: ist("2026-11-20T09:00:00") });
  await enquiryAt("joined", { status: "joined", createdAt: ist("2026-11-10T10:00:00"),
    nextFollowUp: ist("2026-11-18T00:00:00"), updatedAt: ist("2026-11-15T10:00:00") });
  await enquiryAt("later", { status: "new", createdAt: ist("2026-11-10T10:00:00"),
    nextFollowUp: ist("2026-11-25T00:00:00"), updatedAt: ist("2026-11-10T10:00:00") });

  const waSent = [];
  const waMock = http.createServer((req, res) => {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      waSent.push({ url: req.url, body: JSON.parse(body) });
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ messages: [{ id: "wamid.sum" }] }));
    });
  });
  await new Promise((r) => waMock.listen(0, "127.0.0.1", r));
  await db.doc("secrets/whatsapp").set({ phoneNumberId: "PNID", token: "tok", apiBase: `http://127.0.0.1:${waMock.address().port}` });
  await db.doc("settings/institution").set(
    { name: "Apex", currencySymbol: "₹", whatsappSender: "+91 90000 00000", ownerPhone: "98765 43210" }, { merge: true });

  await check("only admins can send the summary; dates are checked", async () => {
    await expectError(call("sendDailySummary", { date: "2026-11-20" }, tTeacher), "PERMISSION_DENIED");
    await expectError(call("sendDailySummary", { date: "20/11/2026" }, tAdmin), "INVALID_ARGUMENT");
  });
  let summary;
  await check("summary maths: IST day, void and other days excluded, due-today not overdue", async () => {
    summary = await call("sendDailySummary", { date: "2026-11-20" }, tAdmin);
    assert.strictEqual(summary.date, "2026-11-20");
    assert.strictEqual(summary.collected, 4500);
    assert.strictEqual(summary.payments, 2);
    assert.strictEqual(summary.absent, 2);
    assert.strictEqual(summary.overdue, 6000);
    assert.strictEqual(summary.newEnquiries, 2);
    assert.strictEqual(summary.missedFollowUps, 1);
    assert.match(summary.params[0], /20 Nov/);
    assert.deepStrictEqual(summary.params.slice(1),
      ["Apex", "₹4,500 from 2 payments", "2", "₹6,000", "2 new, 1 follow-up missed"]);
  });
  await check("every admin gets it in the app", async () => {
    const n = await db.collection("notifications").where("userId", "==", "admin1").where("type", "==", "dailySummary").get();
    assert.strictEqual(n.size, 1);
    assert.match(n.docs[0].data().body, /Collected ₹4,500 from 2 payments\. 2 students absent\. Overdue ₹6,000\./);
    assert.ok(summary.notified >= 1);
  });
  await check("owner gets the daily_summary template on WhatsApp", async () => {
    assert.strictEqual(summary.whatsapp, "sent");
    const msg = waSent[waSent.length - 1];
    assert.strictEqual(msg.body.to, "919876543210");
    assert.strictEqual(msg.body.template.name, "daily_summary");
    assert.deepStrictEqual(msg.body.template.components[0].parameters.map((p) => p.text), summary.params);
  });
  await check("summaries are stored for admins only", async () => {
    await assertSucceeds(adminDb.doc("daily_summaries/2026-11-20").get());
    await assertFails(teacher.doc("daily_summaries/2026-11-20").get());
    await assertFails(adminDb.doc("daily_summaries/2026-11-20").set({ collected: 1 }));
  });
  await check("no owner number: in-app only", async () => {
    await db.doc("settings/institution").update({ ownerPhone: "" });
    const before = waSent.length;
    const r = await call("sendDailySummary", { date: "2026-11-20" }, tAdmin);
    assert.strictEqual(r.whatsapp, "off");
    assert.strictEqual(waSent.length, before);
  });
  waMock.close();

  await env.cleanup();
  console.log(`\n${passed} checks passed${process.exitCode ? ", some FAILED" : ""}`);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
