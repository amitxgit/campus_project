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
const FN = `http://127.0.0.1:5001/${PROJECT}/us-central1`;
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

  await env.cleanup();
  console.log(`\n${passed} checks passed${process.exitCode ? ", some FAILED" : ""}`);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
