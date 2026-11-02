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
3. In *WhatsApp Manager → Message templates*, create the four templates shown on
   the app's **Parent Alerts** page (*Message templates* → copy each one).
   Category **Utility**, language **English**, names exactly `absence_alert`,
   `fee_reminder`, `fee_receipt` and `test_result`. Approval usually takes minutes to a day.
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
