# Attendance check-in: Bluetooth, QR and phone binding

Students mark attendance in one of three ways. All of them write the same
attendance record (`<sessionId>_<studentId>`), so they never duplicate:

| Method | Proves | Notes |
|---|---|---|
| **Bluetooth** (default) | The student's phone is near the teacher's phone | Needs Bluetooth on both phones |
| **QR code** (fallback) | The student saw the live code in the last ~15–20 s | A code can be forwarded live. Turn it off with "Bluetooth only" |
| **Fingerprint / face machine** | The student is physically at the machine | See [firebase_functions/BIOMETRIC.md](../firebase_functions/BIOMETRIC.md) |

## How it works

1. The teacher taps a class. `startAttendanceSession` creates the session, a
   secret only the server and that teacher's phone know, and a short random
   `bleCode`.
2. Every 5 seconds the teacher's phone signs the current step with the secret.
   It shows the result as a QR code and broadcasts it over Bluetooth as one
   128-bit service UUID (`ba7c` + bleCode + step + 8-byte signature), the only
   data iOS lets an app broadcast.
3. The student taps **Mark attendance**. The app listens for the broadcast for
   up to 20 s and sends what it hears to `markAttendance`, together with the
   phone's installation ID.
4. The server checks the signature, that the step is current (server clock),
   that the session is open, that the student is in the class's section, and
   phone binding. Then it writes the record.

## Phone binding

- A student account is linked to the first phone it checks in from. Checking
  in to that account from another phone is refused, so one student can't
  sign in to friends' accounts on their own phone and mark them.
- In each class, one phone can mark only one student.
- The server stores only a hash of the installation ID (`users/{uid}.deviceBinding`,
  `attendance_sessions/{id}/devices/{hash}`).
- **Changing phones or reinstalling the app** gives a new installation ID.
  The admin opens the student in **Users** and taps **Reset phone link**.

## For teachers

- **Keep the attendance screen open.** iPhones only broadcast while the app is
  on screen. Android keeps broadcasting with the screen off, but the app must
  stay open.
- **Bluetooth only** hides the QR and makes the server refuse QR scans for
  that class. Use it once Bluetooth works for your students.
- If Bluetooth can't start (it's off, permission was refused, or the phone
  can't broadcast), the screen says why and the QR keeps working.

## Limits

- A determined student could carry a friend's phone into class. Spot checks
  (calling a few names from the review list) are the deterrent.
- Bluetooth reaches roughly 10–30 m and can reach a neighbouring room. The
  section check rejects students from other classes, and very weak signals
  are ignored.
- A modified app could replay a token it picks up. Enabling Firebase App Check
  (Play Integrity / App Attest) closes that off. It isn't enabled yet.
