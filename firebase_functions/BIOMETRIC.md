# Fingerprint and face-scan attendance

Batchwise can take attendance from the fingerprint and face-scan machines an
institute already has. A punch on the machine marks the student present in the
class running at that time, the same way a QR scan does.

## How it works

1. The machine sends each punch to the `biometric` Cloud Function.
2. The function matches the machine's user ID to a student:
   - the student's `biometricId` field, if it is set;
   - otherwise, the student's college roll number (`collegeRollNo`).
3. If the student's section has a class running, they are marked **present** in
   that class. A punch up to 15 minutes before the class starts counts for that class.
4. If the teacher starts the class after the punch, the punch is applied when the class starts.
5. A mark saved by a teacher or admin (present, absent, late or excused), or by a QR scan, is never overwritten.

Every punch is stored in `biometric_punches`, including punches from IDs that
don't match a student, so they can be checked later.

Punches and QR scans write the same attendance record (`<sessionId>_<studentId>`), so a
student who does both is marked once. A QR scan, or a mark saved by a teacher or admin,
is never changed by a punch.

## Supported machines

- **ZKTeco and eSSL** fingerprint and face terminals with the "cloud server" / ADMS push
  feature. These are the most common in Indian institutes, and they connect directly.
  - The machine must support HTTPS: Firebase only accepts HTTPS.
  - Older machines that only speak HTTP need a small gateway on the local network that
    forwards punches to the JSON endpoint below.
- **Any other system** (Matrix, Hikvision, a custom gateway) can send punches as JSON.

## Setup

### 1. Deploy

Cloud Functions need the Firebase **Blaze** (pay-as-you-go) plan.

```bash
cd firebase_functions && npm ci && npm test
```

```bash
firebase deploy --only functions,firestore:rules,hosting
```

Firebase Hosting forwards `/iclock/...` and `/biometric/...` to the `biometric` function
(see `firebase.json`). Machines therefore connect to the Hosting site,
`batchwise-2bd30.web.app` (the same site that serves `pay.html`), or a custom domain
connected to it. The main web app on Cloudflare Pages does not forward these paths.

### 2. Enrol students on the machine

Enrol each student with their **college roll number** as the machine's user ID.
If the machine needs numeric IDs, put the number you use in a `biometricId` field on
the student, using Admin → Backup & raw data → Users with merge, for example
`[{"id": "<student uid>", "biometricId": "1045"}]`.

### 3. Connect the machine

**ZKTeco / eSSL.** On the machine, open *Comm* → *Cloud Server Setting* and set:

- **Server address:** the Firebase Hosting domain, `batchwise-2bd30.web.app`
- **Port:** `443`
- **HTTPS:** on (if the menu has it)
- **Proxy:** off

On first contact the machine appears in Firestore under `biometric_devices/<serial>`
with `enabled: false`. To approve it, set `enabled: true` there, or import it from
Admin → Backup & raw data → Biometric devices:

```json
[{ "id": "<device serial>", "name": "Main gate", "enabled": true }]
```

Punches are ignored until the device is enabled.

**Other systems.** Create the device yourself with an API key, then POST punches:

```json
[{ "id": "gate-1", "name": "Gate 1 gateway", "enabled": true, "apiKey": "<long random string>" }]
```

```bash
curl -X POST "https://batchwise-2bd30.web.app/biometric/punches" \
  -H "Authorization: Bearer <apiKey>" -H "Content-Type: application/json" \
  -d '{"deviceId":"gate-1","punches":[{"userId":"21CS045","time":"2026-11-04T09:02:00+05:30","method":"face"}]}'
```

`time` must include its time zone. `method` is one of `fingerprint`, `face`, `card` or `palm`.

### 4. Time zone

Machines send local time without a zone. India time (UTC+5:30) is assumed. For a
machine set to another zone, add `utcOffsetMinutes` to its `biometric_devices` document.

## Firestore security rules

`firestore.rules` makes `biometric_devices` readable and writable by admins only, and
`biometric_punches` readable by admins only. Only the Cloud Function writes punches.

## Tests

```bash
cd firebase_functions && npm test
```

The tests cover punch matching, India time, early punches, section checks, manual
marks and QR scans winning, unknown devices and users, and the JSON endpoint's key check.
