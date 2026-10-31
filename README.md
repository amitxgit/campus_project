# 🚀 Campus Track
**By Mohit Chauhan & Yash Gulati**

A comprehensive Flutter application designed to modernize the campus experience. It provides students, teachers, and administrators with a single platform to manage timetables, track attendance via QR codes, handle internal marks, and communicate effectively.

---

## ✨ Features

### 👨‍🎓 For Students
* **Student Dashboard:** A central hub showing overall attendance and the next/ongoing class.
* **QR Code Scanning:** Securely scan a time-limited QR code from the teacher to mark attendance.
* **Attendance History:** A detailed, filterable list of all past attendance records with subject-wise percentages.
* **Internal Marks:** View published internal marks (assignments, tests, attendance) from all teachers in one place.
* **Timetable:** View a full weekly timetable with offline support.
* **Assignments:** See coursework for your section and turn it in with text, links or a file attachment (up to 20 MB). Resubmit any time.
* **Notices:** Announcements addressed to students or everyone.
* **Raise Query:** A simple form to submit academic or administrative queries to the admin.
* **Teacher Directory:** Browse a list of all teachers, their contact info, and their qualifications.

### 👩‍🏫 For Teachers
* **Teacher Dashboard:** A schedule-centric dashboard showing today's classes and what's next.
* **Generate QR:** Generate a unique, time-limited QR code for a class to take attendance.
* **Review Attendance:** A live-updating list of students who have scanned in, with the ability to manually override/edit marks (Present, Absent, Late, Excused).
* **Internal Marks System:** A complete grading page to select a subject, enter marks (Assignment/Test), and see auto-calculated attendance marks. Includes a switch to publish/unpublish grades to students.
* **Assignments:** Create assignments with a due date, then review every submission (late ones flagged) and download attached files.
* **Notices:** Post announcements to students, teachers, or everyone.
* **My Qualifications:** Teachers can add, edit, or remove their academic qualifications from their profile.
* **Student Remarks:** Add private, filterable tags (e.g., "Good," "Needs Improvement") to students, visible only to the teacher.

### 🔐 For Admins
* **Admin Dashboard:** A statistical overview of the entire campus (total users, attendance today, open queries).
* **Full User Management:** Create, edit, and deactivate any user account (Student, Teacher, or Admin).
* **Timetable Builder:** A complete tool to create and delete timetable entries for any section. (Sends real-time notifications to students on changes).
* **Attendance Overrides:** A powerful page to filter and manually override any student's attendance record from any class.
* **Internal Marks Overrides:** A page to filter and manually edit any student's internal marks for any subject.
* **Query Management:** View and resolve all queries submitted by students. (Sends a real-time notification on status change).
* **Password Resets:** Send password reset links to any user.

---

## 🛠️ Tech Stack

* **Framework:** Flutter
* **Backend:** Firebase
    * **Authentication:** For secure email/password login.
    * **Firestore:** Real-time database for all app data.
    * **Firestore & Storage Security Rules:** Secure all data and uploaded files based on user roles.
    * **Cloud Functions:** Server-verified QR attendance, account creation, notification delivery.
    * **Cloud Storage:** Assignment file uploads.
* **State Management:** Flutter Riverpod
* **Navigation:** GoRouter
* **QR & Scanning:** `qr_flutter` & `mobile_scanner`
* **UI & Utilities:**
    * `google_fonts`
    * `intl` (for date/time formatting)
    * `url_launcher` (for teacher directory)
    * `collection` (for data processing)
    * `secure_application` (to block screenshots on the QR page)

---

> **Setting up for a real institute?** Follow [docs/SETUP.md](docs/SETUP.md):
> Firebase plan, first admin, demo data, APK download, and WhatsApp parent alerts.

## 🏁 Getting Started

### 1. Firebase Setup

This project is fully integrated with Firebase. To run it, you must connect it to your own Firebase project.

1.  Create a new project in the [Firebase Console](https://console.firebase.google.com/).
2.  **Enable** the following services:
    * **Authentication** (with the Email/Password sign-in method turned on).
    * **Firestore Database** (start in test mode for now).
    * **Storage**.
3.  Add **Android** and **Web** apps to your project.
    * For **Android**, the package name **must** be `com.batchwise.app`.
4.  Install the Firebase CLI and FlutterFire CLI:
    ```bash
    npm install -g firebase-tools
    dart pub global activate flutterfire_cli
    ```
5.  Log in to Firebase in your terminal:
    ```bash
    firebase login
    ```
6.  Run `flutterfire configure` from the project root to connect your app.
    ```bash
    flutterfire configure
    ```
    > **Note:** Select your new project. When it asks to overwrite files, say **Yes**.
7.  Manually update the Firebase config in `web/firebase-messaging-sw.js` with the one from your Firebase project settings.

### 2. Deploy Security Rules, Indexes and Cloud Functions

QR attendance, creating user logins, and in-app notifications run as Cloud
Functions, which require the Firebase **Blaze** (pay-as-you-go) plan.
Assignment file uploads use **Cloud Storage** (enable it in the console first).

```bash
cd firebase_functions && npm ci && cd ..
firebase deploy --only firestore,functions,storage
```

This publishes `firestore.rules`, `firestore.indexes.json`, `storage.rules` and
the functions in `firebase_functions/`. The first time, the CLI asks to let
Storage rules read Firestore (they check the user's role) — answer **Yes**.

To try everything locally first:

```bash
firebase emulators:start --project demo-campus
```

To run the automated checks for the functions and security rules (needs Java):

```bash
cd tests && npm ci && npm test
```

### 3. Seed the Database (CRITICAL)

Your new database is empty. You must run the seeder script to add all the users, subjects, and timetables.

> **IMPORTANT:** For the seeder to work, you must *temporarily* open your Firestore rules.

1.  In the **Rules** tab of your Firestore console, change the rules to:
    ```javascript
    rules_version = '2';
    service cloud.firestore {
      match /databases/{database}/documents {
        match /{document=**} {
          allow read, write: if true;
        }
      }
    }
    ```
2.  Click **Publish**.
3.  Run the seeder script from your terminal:
    ```bash
    flutter run -t bin/run_seeder.dart
    ```
4.  Wait for it to print `✅ Seeding complete!`.
5.  **IMMEDIATELY** go back to the Firebase console, delete the temporary rules, and paste your **secure rules** back in. Click **Publish**.

### 4. Run the App

You're all set. You can now run the app normally.

```bash
flutter pub get
flutter run
