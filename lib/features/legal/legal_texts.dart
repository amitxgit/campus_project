// lib/features/legal/legal_texts.dart
//
// The privacy policy, terms of use and account-deletion page, written once.
// The app shows them (LegalPage) and `dart run tool/make_legal_pages.dart`
// writes the same text to web/privacy.html, web/terms.html and
// web/delete-account.html (the public URLs Play Store asks for). A test fails
// if the web pages are out of date.
//
// Pure Dart: no Flutter imports, so the tool can use it.
//
// TODO(owner): fill in the placeholders below, run the tool, and have a
// lawyer review the text before launch. It is a careful draft, not legal advice.

const kBusinessName = '[BUSINESS NAME]';
const kBusinessAddress = '[REGISTERED ADDRESS]';
const kContactEmail = '[CONTACT EMAIL]';
const kGrievanceOfficer = '[GRIEVANCE OFFICER NAME]';
const kJurisdictionCity = '[CITY]';
const kLegalUpdated = '2 November 2026';

/// A titled section. Blocks starting with "- " are bullet points.
class LegalSection {
  final String heading;
  final List<String> blocks;
  const LegalSection(this.heading, this.blocks);
}

class LegalDoc {
  final String slug; // web file name without .html
  final String title;
  final String intro;
  final List<LegalSection> sections;
  const LegalDoc({required this.slug, required this.title, required this.intro, required this.sections});
}

const privacyPolicy = LegalDoc(
  slug: 'privacy',
  title: 'Privacy policy',
  intro: 'Batchwise is an app that coaching institutes, schools and colleges use to run attendance, fees, '
      'tests and parent updates. This policy explains what personal data the app holds, why, who can see it, '
      'how long it is kept and how you can exercise your rights under India\'s Digital Personal Data Protection '
      'Act, 2023 (DPDP Act).',
  sections: [
    LegalSection('Who is responsible', [
      'Your institute decides what data to collect and why, so it is the Data Fiduciary for your data. '
          '$kBusinessName ("we"), which provides Batchwise, processes the data only on your institute\'s '
          'instructions, as its Data Processor.',
      'Each institute\'s data is kept in its own separate database. We do not sell personal data, show '
          'advertising, or use it for any purpose of our own.',
    ]),
    LegalSection('What data the app holds', [
      '- Identity and contact: name, mobile number, email, and for students the parent\'s or guardian\'s name '
          'and mobile number.',
      '- Enrolment: batch or class, roll number, and for staff, subjects and qualifications.',
      '- Attendance: which classes a student attended, and when.',
      '- Tests and results: marks, ranks and published results.',
      '- Fees: fee plan, instalments, payments, receipts and the payment reference (for example a UPI '
          'transaction number). The app never stores card or bank details.',
      '- Enquiries: details of people who asked about joining, recorded by the institute.',
      '- Files you upload, such as assignment submissions or an ID photo.',
      '- Private notes that teachers keep about a student\'s progress, visible only to staff.',
      '- Technical data: a notification token for your device and basic error logs.',
    ]),
    LegalSection('Why it is used', [
      'Only to run your institute: taking attendance, managing fees and receipts, publishing results, '
          'sending notices, and keeping parents informed about attendance, fees and results. The legal basis '
          'is your consent, given to your institute when you enrol, and the institute\'s legitimate uses '
          'permitted by the DPDP Act.',
    ]),
    LegalSection('Children', [
      'Many students are under 18. Under the DPDP Act, the institute must obtain verifiable consent from a '
          'parent or guardian before processing a child\'s data. The app does not track children\'s behaviour '
          'or show them targeted advertising.',
    ]),
    LegalSection('Who can see it', [
      '- Students see their own records. Teachers see what they need for their classes. Institute '
          'administrators see everything for their institute.',
      '- Parents receive messages about their own child by WhatsApp, if the institute turns this on.',
      '- Service providers who process data for us, under contract and only to provide the service: Google '
          'Cloud / Firebase (hosting, sign-in and storage, in Mumbai, India); Meta (WhatsApp messages, only '
          'if the institute connects WhatsApp); Razorpay (online fee payments, only if the institute connects '
          'it).',
      '- Authorities, only when Indian law requires it.',
    ]),
    LegalSection('How long it is kept', [
      'Data is kept while you are enrolled or employed at the institute and for as long afterwards as the '
          'institute needs it for its records. Fee and payment records may have to be kept for the period '
          'tax law requires. When data is no longer needed it is deleted. Backups are kept for up to 30 days '
          'and then overwritten.',
    ]),
    LegalSection('Your rights', [
      'You can ask to see a summary of your data, to correct or complete it, or to have it erased, and you can '
          'withdraw your consent. You can also nominate someone to exercise these rights for you if you die or '
          'become unable to.',
      'To delete your account, open Profile, then Request account deletion, or see the account deletion page. '
          'For anything else, contact your institute\'s office first. If you are not satisfied, write to our '
          'Grievance Officer below. We respond within 30 days.',
      'If your complaint is not resolved, you may complain to the Data Protection Board of India.',
    ]),
    LegalSection('Security', [
      'Data is encrypted in transit and at rest by Google Cloud. Access is limited by role, every account '
          'needs a password, and payment and messaging keys are stored where no app user can read them. If a '
          'breach affects your data, we will help your institute inform you and the Data Protection Board as '
          'the law requires.',
    ]),
    LegalSection('Contact and grievances', [
      'Grievance Officer: $kGrievanceOfficer, $kBusinessName, $kBusinessAddress. Email: $kContactEmail.',
    ]),
    LegalSection('Changes', [
      'We will update this policy when the app or the law changes, and show the new date at the top. '
          'Significant changes will be announced in the app.',
    ]),
  ],
);

const termsOfUse = LegalDoc(
  slug: 'terms',
  title: 'Terms of use',
  intro: 'These terms apply to everyone who uses Batchwise: institutes, their staff, students and parents. '
      'By signing in you agree to them.',
  sections: [
    LegalSection('The service', [
      'Batchwise is provided by $kBusinessName to institutes. Your institute gives you your account and '
          'decides which features are on. Your institute, not us, is responsible for its courses, fees, '
          'results and communication with you.',
    ]),
    LegalSection('Your account', [
      'Keep your password private and do not let anyone else use your account. Tell your institute straight '
          'away if you think someone has. You are responsible for what is done with your account.',
    ]),
    LegalSection('Acceptable use', [
      '- Do not try to see or change data you are not meant to, or to get around attendance checks.',
      '- Do not upload anything unlawful, offensive or that you have no right to share.',
      '- Do not disrupt the app, copy it, or use it to send spam.',
      'Your institute may suspend an account that breaks these rules.',
    ]),
    LegalSection('Fees and payments', [
      'Fees are set and collected by your institute. Payments go directly to the institute by UPI or through '
          'its payment provider; $kBusinessName does not receive or hold your money. Questions about fees or '
          'refunds go to your institute.',
    ]),
    LegalSection('Availability', [
      'We work to keep Batchwise available and your data safe, but the app is provided "as is" and may '
          'occasionally be unavailable for maintenance or reasons outside our control.',
    ]),
    LegalSection('Liability', [
      'To the extent the law allows, $kBusinessName is not liable for indirect losses, or for decisions an '
          'institute makes using the app. Nothing in these terms limits rights you have under Indian consumer '
          'protection law.',
    ]),
    LegalSection('Privacy', [
      'How personal data is handled is explained in the privacy policy.',
    ]),
    LegalSection('Law and disputes', [
      'These terms are governed by the laws of India, and the courts at $kJurisdictionCity have jurisdiction.',
    ]),
    LegalSection('Changes and contact', [
      'We may update these terms and will show the new date at the top. Contact: $kBusinessName, '
          '$kBusinessAddress, $kContactEmail.',
    ]),
  ],
);

const accountDeletion = LegalDoc(
  slug: 'delete-account',
  title: 'Delete your Batchwise account',
  intro: 'Students, parents\' contact details, teachers and staff can ask for their Batchwise account and '
      'personal data to be deleted.',
  sections: [
    LegalSection('In the app', [
      'Open the menu, then Profile, then Request account deletion. Your institute\'s administrator sees the '
          'request and deletes the account, normally within 30 days.',
    ]),
    LegalSection('Without the app', [
      'Ask your institute\'s office, or email $kContactEmail with your name, your institute\'s name and the '
          'mobile number or email you sign in with. We will confirm it is you with your institute before '
          'deleting anything.',
    ]),
    LegalSection('What is deleted', [
      '- Your sign-in and profile: name, contact details, parent details, photo and notification settings.',
      '- Your notifications and uploaded files.',
    ]),
    LegalSection('What may be kept', [
      'Records your institute must keep by law, such as fee receipts, may be kept for the period the law '
          'requires and then deleted. Attendance and results may be kept by the institute as part of its '
          'academic records. Backups are overwritten within 30 days.',
    ]),
  ],
);

const legalDocs = [privacyPolicy, termsOfUse, accountDeletion];
