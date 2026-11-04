# Setting up Batchwise for an institute

These are the steps that need an account owner (billing, credentials, store
listings). Everything else is already in the code.

---

## 1. Firebase project (once per institute)

Each institute gets its own Firebase project, so their data is completely
separate. The main project is `batchwise-2bd30` (Firestore and functions in
`asia-south1`, Mumbai).

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
   firebase deploy --only firestore,functions,storage --project batchwise-2bd30
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

To try it with no cloud at all, run `firebase emulators:start --project batchwise-2bd30`,
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
  1. The app ID is `com.batchwise.app` (set in `android/app/build.gradle.kts`).
     It is registered as an Android app in Firebase and its settings are in
     `lib/firebase_options.dart`. Don't change it after publishing.
  2. Create an upload key and set a release signing config (the build is
     currently signed with the debug key).
  3. Google Play Console account: US$25 once.

## 5. Optional: automatic WhatsApp messages to parents

Without this, staff send parent messages from their own WhatsApp with one tap,
and it costs nothing. With it, messages go out automatically from the institute's
number.

1. Create a **Meta Business** account and a **WhatsApp Business Platform** app at
   developers.facebook.com → *Create app* → *Business* → add *WhatsApp*.
2. Add and verify the institute's phone number (it can't already be on the
   normal WhatsApp app).
3. In *WhatsApp Manager → Message templates*, create the five templates shown on
   the app's **Parent Alerts** page (*Message templates* → copy each one).
   Category **Utility**, language **English**, names exactly `absence_alert`,
   `fee_reminder`, `fee_receipt`, `test_result` and `daily_summary` (the owner's
   evening summary, see section 10). Approval usually takes minutes to a day.
   `fee_reminder` and `fee_receipt` have five values; the fifth is the UPI pay
   link (see section 6). In Meta, give it a sample value like
   `https://batchwise-2bd30.web.app/pay.html?pa=apex@ybl&am=5000.00`.
4. Create a **permanent access token**: Business settings → *System users* → add
   an admin system user → *Generate token* with the `whatsapp_business_messaging`
   permission.
5. In the app: **Parent Alerts → Connect WhatsApp**. Enter the business number,
   the *Phone number ID* (from the WhatsApp → API Setup page) and the token,
   then tap **Send test**.

Meta charges per message (utility messages in India cost a few paise each; check
Meta's current rate card), billed to the institute's Meta account.

## 6. Online fee payments by UPI (free, no gateway)

Students and parents pay straight into the institute's bank account from any
UPI app. There's no gateway fee. The office still confirms each payment: when
it shows up in the bank app, record it in **Fees → student → Record payment**
as *UPI* with the UPI reference number.

1. Get the institute's **UPI ID** (e.g. `apexclasses@okhdfcbank`). A business
   UPI ID from the bank or a merchant app (GPay for Business, PhonePe Business,
   Paytm for Business) avoids the daily limits on personal IDs.
2. In the app: **Settings → Online payments**, enter the UPI ID and the name
   on that account, then save.
3. **Publish the pay page.** WhatsApp doesn't make `upi://` links tappable, so
   reminders and receipts link to `pay.html` on the web app, which opens the
   UPI app. Turn on Hosting once (Firebase console → *Build → Hosting* → *Get
   started*), then from the repo root:
   ```bash
   flutter build web
   firebase deploy --only hosting --project batchwise-2bd30
   ```
   This serves the web app and the pay page at `https://batchwise-2bd30.web.app`.
   If the web app is hosted somewhere else, build the phone app with
   `--dart-define=PAY_PAGE_BASE=https://your-site` so links point there.
4. Check it works: open **My Fees** as a student with a balance and tap **Pay**,
   or send yourself a fee reminder and tap the link.


## 7. Optional: Razorpay payment links (automatic recording)

With UPI (section 6) the office has to record each payment by hand. With
Razorpay, the office sends a payment link from the app, the parent pays by UPI,
card or netbanking, and the payment is recorded with a receipt number
automatically. Razorpay charges a fee on each payment (about 2%; check their
current pricing) and settles the money to the institute's bank account.

1. **Sign up** at razorpay.com with the institute's details and finish **KYC**
   (PAN, bank account, business proof). Live payments only work after KYC is
   approved, which can take a few days. Test mode works straight away.
2. **API keys.** Razorpay Dashboard → *Account & Settings* → *API keys* →
   *Generate key*. Note the **Key ID** (`rzp_live_…` or `rzp_test_…`) and the
   **Key secret** (shown once).
3. **Webhook.** Deploy the functions first (section 1, step 3), then Razorpay
   Dashboard → *Account & Settings* → *Webhooks* → *Add new webhook*:
   - URL: `https://asia-south1-batchwise-2bd30.cloudfunctions.net/razorpayWebhook`
     (the deploy output prints it too; use the project ID of this institute).
   - Secret: make up a long random password and keep it for the next step.
   - Active events: tick only **payment_link.paid**.
4. **In the app:** **Settings → Online payments → Connect Razorpay**, then enter
   the Key ID, Key secret and webhook secret. They're stored write-only:
   nobody can read them back in the app.
5. **Check it works** (in test mode first): open a student's fees, tap the
   **link** icon (*Send payment link*), create a link for a small amount, open
   it and pay with Razorpay's test UPI ID `success@razorpay`. Within a few
   seconds the payment appears on the student's fees with a receipt number.
   When you switch to live keys, add the webhook again in live mode and enter
   the live keys with **Update keys**.

The link goes to the parent in the `fee_reminder` WhatsApp message (as its pay
link), so no new Meta template is needed. If Razorpay pays for a student with
no fee plan, the payment is logged in Cloud Functions logs and marked
`paidNoAccount` in `payment_links`; set up the plan and record it by hand.

## 8. Enquiries & admissions

Nothing to sign up for. After updating the app, deploy the Firestore rules
once so the new `enquiries` collection is allowed:
```bash
firebase deploy --only firestore:rules --project batchwise-2bd30
```
Admins see **Enquiries** on the home screen and in the menu. Teachers get a
**New enquiry** button for walk-ins but can't see the list. **Convert to
student** opens Add User already filled in from the enquiry, then offers to set
up the fee plan.

## 9. Reports, PDFs and exports

Nothing to sign up for. Deploy the rules **and indexes** once after updating:
```bash
firebase deploy --only firestore --project batchwise-2bd30
```
The fee ledger reads every student's payments at once, which needs the
`payments.paidOn` index from `firestore.indexes.json`. Without it the ledger
fails with "requires an index"; the index takes a few minutes to build after
deploying.

- **Receipts:** tap a payment → *PDF*. Students get the same button in My Fees.
- **Report cards:** **Reports → Report card**, pick a student and optionally
  include fee status. Students can download their own from **Results**.
- **Spreadsheets:** **Reports** → fee ledger, dues list, batch attendance or
  test results. They open in Excel or Google Sheets.

On a phone these open the share sheet (WhatsApp, Drive, email); in a browser
they download.

## 10. Owner's daily summary (8 pm)

Every evening at 8 pm (India time) each admin gets a notification in the app
with the day's fee collections, students absent, total overdue fees, new
enquiries and follow-ups that were missed.

1. **Deploy the functions** (section 1, step 3). The 8 pm run uses Cloud
   Scheduler, which the Blaze plan includes (3 free jobs a month; this is one).
   If the deploy asks to enable the Cloud Scheduler API, answer **Yes**.
2. **Optional, on WhatsApp too:** with WhatsApp connected (section 5) and the
   `daily_summary` template approved, open **Parent Alerts → Daily summary → ⋮
   → Add owner's WhatsApp** and enter the owner's number. In Meta, give the
   template sample values like `Mon, 2 Nov`, `Apex Classes`,
   `₹12,500 from 4 payments`, `3`, `₹1,20,000` and `2 new, 1 follow-up missed`.
3. **Check it:** **Parent Alerts → Daily summary → ⋮ → Send today's now**, then
   look in Notifications (and on the owner's WhatsApp).

The 8 pm run sends once a day even if Cloud Scheduler retries. Each day's
figures are kept in `daily_summaries` in Firestore.

## 11. Daily backups of the database

Firestore doesn't back itself up. This exports everything every night at 2:30
am to a storage bucket and deletes exports after 30 days (the privacy policy
promises backups are overwritten within 30 days). Run once, in Google Cloud
Shell (console.cloud.google.com, the `>_` button) for project `batchwise-2bd30`:

```bash
PROJECT=batchwise-2bd30
BUCKET=gs://$PROJECT-backups
gcloud config set project $PROJECT
gcloud services enable cloudscheduler.googleapis.com firestore.googleapis.com

# A bucket in Mumbai that deletes exports older than 30 days.
gcloud storage buckets create $BUCKET --location=asia-south1 --uniform-bucket-level-access
echo '{"rule":[{"action":{"type":"Delete"},"condition":{"age":30}}]}' > lifecycle.json
gcloud storage buckets update $BUCKET --lifecycle-file=lifecycle.json

# A service account that may only export the database and write the bucket.
gcloud iam service-accounts create firestore-backup --display-name="Firestore backup"
SA=firestore-backup@$PROJECT.iam.gserviceaccount.com
gcloud projects add-iam-policy-binding $PROJECT --member=serviceAccount:$SA --role=roles/datastore.importExportAdmin
gcloud storage buckets add-iam-policy-binding $BUCKET --member=serviceAccount:$SA --role=roles/storage.admin

# Every night at 2:30 am IST. Each run makes its own dated folder.
gcloud scheduler jobs create http firestore-daily-export \
  --location=asia-south1 --schedule="30 2 * * *" --time-zone="Asia/Kolkata" \
  --uri="https://firestore.googleapis.com/v1/projects/$PROJECT/databases/(default):exportDocuments" \
  --http-method=POST --headers="Content-Type=application/json" \
  --message-body="{\"outputUriPrefix\":\"$BUCKET\"}" \
  --oauth-service-account-email=$SA \
  --oauth-token-scope=https://www.googleapis.com/auth/datastore
```

Check it: `gcloud scheduler jobs run firestore-daily-export --location=asia-south1`,
wait a minute, then `gcloud storage ls $BUCKET` should show a dated folder.

**Cost:** each export reads every document once (a few hundred students is a
few thousand reads, well inside the free 50,000 a day) plus a few paise of
storage. Cloud Scheduler gives 3 free jobs per billing account; this and the
8 pm summary use two.

**Restoring** overwrites documents with the backed-up versions, so do it only
when you mean to:
`gcloud firestore import gs://batchwise-2bd30-backups/<dated-folder>`.
Uploaded files (assignment submissions) are in Cloud Storage and aren't part
of this export.

## 12. Before launch: legal pages and Play Store

1. Open `lib/features/legal/legal_texts.dart` and replace `[BUSINESS NAME]`,
   `[REGISTERED ADDRESS]`, `[CONTACT EMAIL]`, `[GRIEVANCE OFFICER NAME]` and
   `[CITY]`. Have a lawyer review the privacy policy and terms; they are a
   careful draft, not legal advice.
2. Regenerate the web pages and publish them:
   ```bash
   dart run tool/make_legal_pages.dart
   flutter build web
   firebase deploy --only hosting --project batchwise-2bd30
   ```
   They are then at `https://batchwise-2bd30.web.app/privacy.html`,
   `/terms.html` and `/delete-account.html` (Play asks for the first and last).
3. Deploy rules and functions (account deletion requests and the extra
   clean-up when an account is deleted):
   `firebase deploy --only firestore,functions --project batchwise-2bd30`.
4. Work through `docs/PLAY_STORE.md`: store listing, Data safety answers and
   the decisions marked **Decide**.

Account deletion requests appear as a banner on the admin home. Act on them
within 30 days. An admin's own request has to be handled by another admin; if
you are the only admin, delete the account in the Firebase console instead.

## 13. Attendance: Bluetooth check-in and phone binding

Nothing to sign up for. How it works and its limits are in
[CHECK_IN.md](CHECK_IN.md). Fingerprint and face-scan machines are in
[firebase_functions/BIOMETRIC.md](../firebase_functions/BIOMETRIC.md).

**Release the app and the functions together.** The new `markAttendance`
requires the phone ID that only the new app sends. Installed copies of an
older version can't mark attendance (students see "Please update the app")
until they update. So:

1. Build and publish the new app (section 4), so students can update.
2. Deploy the functions and rules the same day:
   ```bash
   firebase deploy --only firestore:rules,functions --project batchwise-2bd30
   ```
3. Ask students to update the app before their next class.

**Phones.** The first time, teachers and students are asked to allow
Bluetooth ("Nearby devices" on Android). On iPhones the app needs iOS 13 or
later, and teachers must keep the attendance screen open while students check
in, because iPhones stop broadcasting in the background.

**Changing phones.** A student account checks in from one phone only. After a
new phone, a reinstall or clearing the app's data, the admin opens the student
in **Users** and taps **Reset phone link**.

**Bluetooth only.** Once check-in works for a class, the teacher can turn on
**Bluetooth only** on the attendance screen. The QR is hidden and the server
refuses QR scans for that class.
