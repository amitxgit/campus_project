# Publishing Batchwise on Google Play

A checklist and draft answers for Play Console. Check each answer against the
current form: Google changes the wording now and then. Items marked
**Decide** need your call.

---

## 1. Before you start

- [ ] Fill the placeholders in `lib/features/legal/legal_texts.dart` (business
      name, address, contact email, grievance officer, city), run
      `dart run tool/make_legal_pages.dart`, deploy hosting, and have a lawyer
      read the text. See SETUP.md section 12.
- [ ] Release signing: create an upload key and a release signing config
      (the build is currently signed with the debug key). Use Play App Signing.
- [ ] Play Console developer account (US$25 once). An **organisation**
      account needs a D-U-N-S number; a personal account needs 12 testers for
      14 days of closed testing before production.
- [ ] A demo Firebase project with the demo institute (SETUP.md section 3), so
      reviewers can sign in.

## 2. Store listing

| Item | Requirement | Suggestion |
|---|---|---|
| App name | up to 30 characters | `Batchwise` (check no clash in Play and trademarks) |
| Short description | up to 80 characters | `Attendance, fees, tests and parent alerts for coaching institutes.` |
| Full description | up to 4000 characters | Lead with "recover overdue fees, keep parents informed"; then attendance, fees and UPI, WhatsApp alerts, tests and ranks, enquiries, reports. |
| App icon | 512 × 512 PNG, 32-bit, up to 1 MB | export from `assets/icon/app_icon.png` |
| Feature graphic | 1024 × 500 PNG/JPG, no transparency | black background, BrandMark + "Fees, attendance, parents. Sorted." |
| Phone screenshots | 2–8, 16:9 or 9:16, 320–3840 px per side | admin home, fees with overdue, Pay by UPI, parent WhatsApp message, test results with ranks, enquiries, report card PDF |
| Tablet screenshots | optional (needed for "designed for tablets") | skip at first |
| Category | | Education |
| Contact email | shown publicly | your support email |
| Privacy policy URL | required | `https://batchwise-2bd30.web.app/privacy.html` |

## 3. App content declarations

**Privacy policy:** the URL above.

**App access:** "All or some functionality is restricted." Give reviewers the
demo logins (password `Demo@123`): admin `admin@apex.demo`, teacher
`phy@apex.demo`, student mobile `9710000000`. Say the app is used by
institutes that create accounts for their students and staff, and that there
is no public sign-up.

**Ads:** No, the app contains no ads.

**Content rating:** fill the questionnaire as a reference/education app with
no user-generated public content, violence, gambling or purchases of digital
goods. Expect "Everyone"/"3+".

**Target audience and content** (**Decide**): students at coaching institutes
are often under 18 and can be under 13. If you include ages under 13, the app
falls under Google Play's Families policy (stricter rules, teacher-approved
review). If institutes only enrol students 13+, choose 13–15, 16–17 and 18+.
Either way, the app has no ads and no tracking, which keeps the Families
requirements manageable.

**News app:** No. **Government app:** No. **Health:** No.

**Financial features** (**Decide**): the app shows fees and links to UPI or
Razorpay but doesn't move money itself; the money goes straight to the
institute. "My app doesn't provide any financial features" is the likely
answer; read Google's definitions before submitting.

## 4. Data safety form (draft)

**Does your app collect or share any of the required user data types?** Yes.

**Is all of the user data collected by your app encrypted in transit?** Yes
(HTTPS to Google Cloud / Firebase).

**Do you provide a way for users to request that their data is deleted?**
Yes: in the app (Profile → Request account deletion) and at
`https://batchwise-2bd30.web.app/delete-account.html`.

**Data shared with third parties:** none. Google Firebase, Meta (WhatsApp) and
Razorpay process data on the institute's behalf as service providers, which
Play doesn't count as sharing. Parents receive messages about their own child
at the institute's request.

Data **collected** (for each: collected, not shared; processed ephemerally:
No; required or optional as shown; purposes):

| Play category | Data type | What it is in Batchwise | Required? | Purposes |
|---|---|---|---|---|
| Personal info | Name | student, staff and parent names | Required | App functionality, Account management |
| Personal info | Email address | sign-in email (optional for students) | Optional | Account management, App functionality |
| Personal info | Phone number | student and parent mobile numbers | Required | App functionality, Account management, Developer communications (parent alerts) |
| Personal info | User IDs | the account ID | Required | Account management |
| Personal info | Other info | batch, roll number, parent relationship, enquiry details | Required | App functionality |
| Financial info | Other financial info | fee plans, payments, receipts, UPI/Razorpay references (no card or bank numbers) | Optional (fees can be off) | App functionality |
| Messages | Other in-app messages | student queries to staff, teacher remarks | Optional | App functionality |
| Photos and videos / Files and docs | Files and docs | assignment submissions | Optional | App functionality |
| App activity | Other user-generated content | attendance, marks, results | Required | App functionality |
| Device or other IDs | Device or other IDs | push notification token | Required | App functionality |

Not collected: location, contacts, calendar, health, audio, web browsing,
search history, installed apps, crash logs or analytics (no Crashlytics or
Analytics in the app). If you add Crashlytics or Analytics later, update this
form.

## 5. Release

1. Build an app bundle: `flutter build appbundle --release` (needs the release
   signing config).
2. Internal testing track first, then closed testing (required for personal
   accounts), then production.
3. After publishing, keep the privacy policy URL working: Google checks it.
