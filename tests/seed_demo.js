// Fills a Firebase project with a realistic demo coaching institute
// ("Apex Classes"): settings, staff, 24 students in two batches, subjects,
// timetable, two weeks of attendance, fee plans with payments, published
// tests, notices and assignments.
//
// Emulators (safe, default):
//   firebase emulators:start --project batchwise-2bd30      (in the repo root)
//   cd tests && npm run seed-demo
//
// A real project (writes real data; use a fresh demo project):
//   GOOGLE_APPLICATION_CREDENTIALS=service-account.json \
//     node seed_demo.js --project YOUR_PROJECT_ID --real-project
const admin = require("firebase-admin");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");

const args = process.argv.slice(2);
const projectId = args.includes("--project") ? args[args.indexOf("--project") + 1] : "batchwise-2bd30";
const real = args.includes("--real-project");
if (!real) {
  process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
  process.env.FIREBASE_AUTH_EMULATOR_HOST ||= "127.0.0.1:9099";
}
admin.initializeApp({ projectId });
const db = admin.firestore();

// Deterministic "random" so every seed looks the same.
let seed = 42;
const rand = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
const pick = (arr) => arr[Math.floor(rand() * arr.length)];

const PASSWORD = "Demo@123";
const BATCHES = ["JEE-2027-A", "NEET-2027-B"];
const SLOTS = [["07:00", "08:30"], ["08:30", "10:00"], ["16:00", "17:30"], ["17:30", "19:00"]];
const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const FIRST = ["Aarav", "Ananya", "Vivaan", "Diya", "Aditya", "Isha", "Arjun", "Kavya", "Rohan", "Meera", "Kabir", "Saanvi",
  "Reyansh", "Anika", "Ishaan", "Myra", "Dhruv", "Tara", "Vihaan", "Riya", "Ayaan", "Navya", "Krish", "Pari"];
const LAST = ["Sharma", "Verma", "Gupta", "Singh", "Patel", "Iyer", "Reddy", "Nair", "Joshi", "Mehta", "Kapoor", "Bose"];

async function upsertUser(uid, email, profile) {
  try {
    await admin.auth().createUser({ uid, email, password: PASSWORD, displayName: profile.name });
  } catch (e) {
    if (e.code !== "auth/uid-already-exists" && e.code !== "auth/email-already-exists") throw e;
  }
  await db.collection("users").doc(uid).set({
    email, isActive: true, isAdmin: false, qualifications: [], phone: "",
    createdAt: FieldValue.serverTimestamp(), ...profile,
  });
}

const day = (offset) => {
  const d = new Date();
  d.setHours(9, 0, 0, 0);
  d.setDate(d.getDate() + offset);
  return d;
};

(async () => {
  console.log(`Seeding demo data into ${real ? "REAL project" : "emulators"} (${projectId})...`);

  await db.doc("settings/institution").set({
    name: "Apex Classes", type: "coaching", groupLabel: "Batch", groups: BATCHES,
    periodStarts: SLOTS.map((s) => s[0]), periodMinutes: 90, workingDays: DAYS,
    attendanceThreshold: 80, assignmentMax: 12, testMax: 12, attendanceMax: 6,
    internalMarksEnabled: false, remarksEnabled: true, feesEnabled: true, testsEnabled: true,
    parentAlertsEnabled: true, autoAbsenceAlerts: false, whatsappSender: "", currencySymbol: "₹",
  });

  // --- Staff -----------------------------------------------------------------
  await upsertUser("demo_admin", "admin@apex.demo", { role: "admin", name: "Neha Kulkarni (Admin)", phone: "9800000001" });
  const teachers = [
    { id: "demo_t_phy", name: "Rajesh Iyer", subject: "Physics", code: "PHY" },
    { id: "demo_t_chem", name: "Sunita Rao", subject: "Chemistry", code: "CHM" },
    { id: "demo_t_math", name: "Vikram Sethi", subject: "Mathematics", code: "MTH" },
    { id: "demo_t_bio", name: "Farah Khan", subject: "Biology", code: "BIO" },
  ];
  for (const t of teachers) {
    await upsertUser(t.id, `${t.id.replace("demo_t_", "")}@apex.demo`, {
      role: "teacher", name: t.name, phone: `98000001${teachers.indexOf(t)}0`,
      qualifications: [`M.Sc. ${t.subject}`, "8+ years teaching"],
    });
  }

  // --- Subjects & timetable ----------------------------------------------------
  const plan = { "JEE-2027-A": ["demo_t_phy", "demo_t_chem", "demo_t_math"], "NEET-2027-B": ["demo_t_phy", "demo_t_chem", "demo_t_bio"] };
  const subjects = [];
  const batch = db.batch();
  for (const b of BATCHES) {
    plan[b].forEach((tid, i) => {
      const t = teachers.find((x) => x.id === tid);
      const id = `demo_sub_${b}_${t.code}`;
      subjects.push({ id, section: b, teacherId: tid, name: t.subject });
      batch.set(db.collection("subjects").doc(id), { code: t.code, name: t.subject, department: "", semester: "", section: b, teacherId: tid });
      DAYS.forEach((d, di) => {
        // Each subject twice a week-ish, rotating through the slots.
        if ((di + i) % 3 === 2) return;
        const slot = SLOTS[(di + i) % SLOTS.length];
        batch.set(db.collection("timetable").doc(`demo_tt_${b}_${t.code}_${d}`), {
          subjectId: id, dayOfWeek: d, startTime: slot[0], endTime: slot[1],
          room: b.startsWith("JEE") ? "Hall A" : "Hall B", section: b, teacherIds: [tid],
        });
      });
    });
  }
  await batch.commit();

  // --- Students ---------------------------------------------------------------
  const students = [];
  for (let i = 0; i < 24; i++) {
    const b = BATCHES[i % 2];
    const name = `${FIRST[i]} ${pick(LAST)}`;
    const mobile = `97${String(10000000 + i * 37311).slice(0, 8)}`;
    const uid = `demo_s_${i + 1}`;
    // Mobile-number login, like most coaching students.
    await upsertUser(uid, `${mobile}@students.campustrack.app`, {
      role: "student", name, phone: mobile, section: b, collegeRollNo: String(101 + i),
      parentName: `Mr./Mrs. ${name.split(" ")[1]}`, parentPhone: `96${String(20000000 + i * 51123).slice(0, 8)}`,
    });
    // Attendance tendency: most students regular, a few irregular.
    students.push({ uid, name, section: b, mobile, reliability: i % 7 === 3 ? 0.6 : 0.88 + rand() * 0.1 });
  }

  // --- Two weeks of attendance ------------------------------------------------
  let writes = db.batch();
  let count = 0;
  const flush = async () => {
    if (count) await writes.commit();
    writes = db.batch();
    count = 0;
  };
  for (let offset = -14; offset <= -1; offset++) {
    const date = day(offset);
    const dname = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][date.getDay()];
    if (!DAYS.includes(dname)) continue;
    for (const sub of subjects) {
      const sessionId = `demo_sess_${sub.id}_${offset}`;
      for (const s of students.filter((x) => x.section === sub.section)) {
        writes.set(db.collection("attendance").doc(`${sessionId}_${s.uid}`), {
          sessionId, studentId: s.uid, subjectId: sub.id, date: Timestamp.fromDate(date), slot: "",
          status: rand() < s.reliability ? "present" : "absent", markedByTeacherId: sub.teacherId,
          markedAt: Timestamp.fromDate(date),
        });
        if (++count >= 400) await flush();
      }
    }
  }
  await flush();

  // --- Fees ------------------------------------------------------------------
  let receipt = 0;
  for (const [i, s] of students.entries()) {
    const total = s.section.startsWith("JEE") ? 90000 : 84000;
    const discount = i % 6 === 0 ? 6000 : 0;
    const net = total - discount;
    const each = Math.floor(net / 3);
    const instalments = [0, 1, 2].map((k) => ({
      label: `Instalment ${k + 1}`,
      amount: k === 2 ? net - each * 2 : each,
      dueDate: Timestamp.fromDate(day(-60 + k * 45)),
    }));
    // Most paid the first instalment; some the second; a few are behind.
    const paidParts = i % 5 === 0 ? 0.5 : i % 3 === 0 ? 1 : i % 4 === 0 ? 3 : 2;
    const payments = [];
    for (let k = 0; k < Math.floor(paidParts); k++) payments.push({ amount: instalments[k].amount, on: day(Math.min(-58 + k * 45, -1)) });
    if (paidParts % 1) payments.push({ amount: Math.round(each / 2), on: day(-55) });
    const paid = payments.reduce((t, p) => t + p.amount, 0);
    const ref = db.collection("fee_accounts").doc(s.uid);
    await ref.set({
      studentName: s.name, section: s.section, totalFee: total, discount, instalments,
      paidAmount: paid, note: discount ? "Merit scholarship" : "", updatedAt: FieldValue.serverTimestamp(),
    });
    for (const p of payments) {
      receipt++;
      await ref.collection("payments").doc(`demo_pay_${receipt}`).set({
        amount: p.amount, mode: pick(["upi", "upi", "cash", "bankTransfer"]), reference: "", note: "",
        paidOn: Timestamp.fromDate(p.on), receiptNo: receipt, receivedBy: "Neha Kulkarni", voided: false,
      });
    }
  }
  await db.doc("meta/counters").set({ receiptSeq: receipt });

  // --- Tests -----------------------------------------------------------------
  const tests = [
    { name: "Weekly Test 1", subject: "Physics", offset: -12, max: 120 },
    { name: "Weekly Test 2", subject: "Chemistry", offset: -7, max: 120 },
    { name: "Monthly Mock", subject: "", offset: -2, max: 300 },
  ];
  for (const b of BATCHES) {
    for (const [ti, t] of tests.entries()) {
      const testId = `demo_test_${b}_${ti}`;
      const roster = students.filter((s) => s.section === b);
      const marks = {};
      for (const s of roster) {
        marks[s.uid] = rand() < 0.08 ? null : Math.round(t.max * Math.min(0.98, 0.35 + rand() * 0.45 + s.reliability * 0.15));
      }
      const present = Object.entries(marks).filter(([, m]) => m !== null).sort((a, z) => z[1] - a[1]);
      const ranks = {};
      present.forEach(([id, m], idx) => {
        ranks[id] = idx > 0 && m === present[idx - 1][1] ? ranks[present[idx - 1][0]] : idx + 1;
      });
      const avg = present.reduce((x, [, m]) => x + m, 0) / present.length;
      const highest = present[0][1];
      await db.collection("tests").doc(testId).set({
        name: t.name, section: b, subjectName: t.subject, date: Timestamp.fromDate(day(t.offset)), maxMarks: t.max,
        createdBy: "demo_t_phy", published: true, appeared: present.length, average: avg, highest,
      });
      await db.collection("tests").doc(testId).collection("marks").doc("all").set({
        scores: Object.fromEntries(present), absent: Object.keys(marks).filter((k) => marks[k] === null),
      });
      for (const s of roster) {
        await db.collection("student_results").doc(s.uid).set({ results: { [testId]: {
          testName: t.name, subjectName: t.subject, date: Timestamp.fromDate(day(t.offset)), maxMarks: t.max,
          marks: marks[s.uid], rank: ranks[s.uid] || null, outOf: present.length, average: avg, highest,
        } } }, { merge: true });
      }
    }
  }

  // --- Notices & assignments -------------------------------------------------
  await db.collection("notices").doc("demo_notice_1").set({
    title: "Diwali break", content: "Classes will remain closed from 30 Oct to 3 Nov. Revision sheets will be shared on the app.",
    targetAudience: "all", authorId: "demo_admin", authorName: "Neha Kulkarni", authorRole: "admin", createdAt: Timestamp.fromDate(day(-3)),
  });
  await db.collection("notices").doc("demo_notice_2").set({
    title: "Monthly mock results are out", content: "Check My Results for your rank. Doubt-clearing session on Saturday 5 PM.",
    targetAudience: "students", authorId: "demo_t_phy", authorName: "Rajesh Iyer", authorRole: "teacher", createdAt: Timestamp.fromDate(day(-1)),
  });
  for (const b of BATCHES) {
    await db.collection("assignments").doc(`demo_asg_${b}`).set({
      title: "Kinematics problem set", description: "Solve questions 1-25 from Module 2. Upload a photo or PDF of your work.",
      teacherId: "demo_t_phy", subjectId: `demo_sub_${b}_PHY`, subjectName: "Physics", section: b,
      dueDate: Timestamp.fromDate(day(4)), createdAt: Timestamp.fromDate(day(-2)),
    });
  }

  console.log("\nDone. Demo logins (password for all: Demo@123):");
  console.log("  Admin    admin@apex.demo");
  console.log("  Teacher  phy@apex.demo   (also chem@, math@, bio@)");
  console.log(`  Student  ${students[0].mobile}   (${students[0].name}, ${students[0].section}) — signs in with mobile number`);
  process.exit(0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
