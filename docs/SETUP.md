# Setting up Campus Track for an institute

These are the steps that need an account owner (billing, credentials, store
listings). Everything else is already in the code.

---

## 1. Firebase project (once per institute)

Each institute gets its own Firebase project, so their data is completely
separate. For your first demo, use the existing project `campus-7b240`.

1. **Upgrade to the Blaze plan.** Firebase console → ⚙ → *Usage and billing* →
   *Modify plan* → Blaze. Cloud Functions need it. A coaching institute of a few
   hundred students normally stays inside the free allowances; set a **budget
   alert of ₹500/month** at the same time (*Usage and billing → Details & settings*).
2. **Turn on the services** (Build menu in the console):
   - *Authentication* → Sign-in method → enable **Email/Password**.
   - *Firestore Database* → Create database. Pick region `asia-south1` (Mumbai)
     for a new project.
   - *Storage* → Get started.
3. **Deploy the backend** from the repo root on your computer:
   ```bash
   npm install -g firebase-tools
   firebase login
   cd firebase_functions && npm ci && cd ..
   firebase deploy --only firestore,functions,storage --project campus-7b240
   ```
   When asked whether Storage rules may read Firestore, answer **Yes**.

## 2. Create the first admin

A new project has no users, and only admins can create users.

1. Firebase console → *Authentication* → *Add user* → enter your email and a
   password. Copy the **User UID** it shows.
2. *Firestore Database* → *Start collection* `users` → Document ID = that UID →
   add fields:
   - `role` (string) = `admin`
   - `name` (string) = your name
   - `email` (string) = the same email
   - `isActive` (boolean) = `true`
3. Sign in to the app with that email. Open **Institute Settings**, choose
   *Coaching Institute*, enter the name and add your batches. Then use
   **Import Students** or **Users** for everyone else.

## 3. Optional: load the demo institute

For sales demos you can fill a **separate** Firebase project with "Apex
Classes" (24 students, fees, tests, attendance). Never run this on a real
customer's project.

1. Console → ⚙ Project settings → *Service accounts* → *Generate new private
   key*. Keep this file secret and out of git.
2. ```bash
   cd tests && npm ci
   GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json node seed_demo.js --project YOUR_DEMO_PROJECT --real-project
   ```
3. Demo logins (password `Demo@123`): admin `admin@apex.demo`, teacher
   `phy@apex.demo`, student mobile `9710000000`.

To try it with no cloud at all, run `firebase emulators:start --project campus-7b240`,
then `cd tests && npm run seed-demo`, and start the app with
`flutter run -d chrome --dart-define=USE_EMULATORS=true`.

## 4. Get the apps

- **Web:** `.github/workflows/deploy.yml` publishes to Cloudflare Pages on every
  push to `main`. Add the repo secret `CLOUDFLARE_API_TOKEN` (GitHub → Settings
  → Secrets and variables → Actions) or upload `build/web` anywhere static.
- **Android APK (for testing):** every push builds one. GitHub → *Actions* →
  *Build Android APK* → latest run → *Artifacts* → `campus-track-apk`. Install it
  on a phone (allow "install unknown apps").
- **Play Store (before selling):**
  1. Choose a real app ID, e.g. `in.yourbrand.campus`, and replace
     `com.example.campus_track` in `android/app/build.gradle.kts`.
  2. Register that ID as a new Android app in Firebase, then run
     `flutterfire configure` to regenerate `lib/firebase_options.dart`.
  3. Create an upload key and set a release signing config (the build is
     currently signed with the debug key).
  4. Google Play Console account: US$25 once.

## 5. Optional: automatic WhatsApp messages to parents

Without this, staff send parent messages from their own WhatsApp with one tap,
and it costs nothing. With it, messages go out automatically from the institute's
number.

1. Create a **Meta Business** account and a **WhatsApp Business Platform** app at
   developers.facebook.com → *Create app* → *Business* → add *WhatsApp*.
2. Add and verify the institute's phone number (it can't already be on the
   normal WhatsApp app).
3. In *WhatsApp Manager → Message templates*, create the four templates shown on
   the app's **Parent Alerts** page (*Message templates* → copy each one).
   Category **Utility**, language **English**, names exactly `absence_alert`,
   `fee_reminder`, `fee_receipt` and `test_result`. Approval usually takes minutes to a day.
4. Create a **permanent access token**: Business settings → *System users* → add
   an admin system user → *Generate token* with the `whatsapp_business_messaging`
   permission.
5. In the app: **Parent Alerts → Connect WhatsApp**. Enter the business number,
   the *Phone number ID* (from the WhatsApp → API Setup page) and the token,
   then tap **Send test**.

Meta charges per message (utility messages in India cost a few paise each; check
Meta's current rate card), billed to the institute's Meta account.
