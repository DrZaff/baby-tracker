# Little Log

A shared baby tracker for iPhone. Everyone who cares for the baby signs in with Google, logs feeds, diapers, weight, milestones, daycare drop-offs and photos, and gets a notification when someone else logs something.

## What it does

- **Today**: a daily report (feeds, breast time per side, bottle and pumped amounts, wet and dirty diapers, daycare times, weight), "last feed", "next side" and "last diaper" at a glance, one-tap logging, and a timeline you can scroll back day by day. Tap any entry to edit it, swipe to delete.
- **Feeds**: breastfeeding with a left/right timer, bottle (formula or breast milk), pumping with per-side timers and amount, or any combination in one entry.
- **Diapers**: pee, poop or both, with optional stool color and consistency.
- **Weight, milestones, daycare** drop-off and pick-up.
- **Trends**: week and month charts by day, a year view by month (daily averages), plus a growth chart.
- **Photos**: share photos with the family, add captions, save or share them.
- **Family**: several babies, invite caregivers by their Google email, units (oz/lb or ml/kg).

Built with SwiftUI, Swift Charts and Firebase (Google sign-in, Firestore, Storage, push notifications through Cloud Functions).

## Set up (one time)

You need a Mac with Xcode, an Apple Developer Program membership ($99/year, needed for notifications and TestFlight), and a Google account for Firebase.

### 1. Firebase project

1. Go to [console.firebase.google.com](https://console.firebase.google.com), click **Add project**, name it (for example `little-log`). Analytics can be off.
2. Upgrade to the **Blaze** (pay as you go) plan under the gear icon > Usage and billing. Photo storage and notifications require it. A family's usage fits in the free allowance; set a budget alert of a few dollars to be safe.
3. **Authentication** > Get started > Sign-in method > enable **Google**.
4. **Firestore Database** > Create database > production mode, pick a region near you.
5. **Storage** > Get started > production mode.
6. Project settings (gear) > General > **Add app** > iOS. Bundle ID: `com.drzaff.littlelog` (or whatever you put in `Config.xcconfig`). Download **GoogleService-Info.plist** and put it in the `LittleLog/` folder of this repo.

### 2. Push notifications

1. At [developer.apple.com](https://developer.apple.com/account/resources/authkeys/list) > Keys, create a key with **Apple Push Notifications service (APNs)** enabled. Download the `.p8` file and note the Key ID and your Team ID.
2. In Firebase: Project settings > **Cloud Messaging** > Apple app configuration > upload the `.p8` key with its Key ID and Team ID.

### 3. Deploy the rules and the notification function

In Terminal, from this repo:

```sh
npm install -g firebase-tools
firebase login
cd firebase
firebase use --add            # pick your project
(cd functions && npm install)
firebase deploy               # rules + notification function
```

### 4. Build the app

```sh
brew install xcodegen
```

1. Open `Config.xcconfig` and fill in `APP_TEAM_ID` (developer.apple.com > Membership) and `REVERSED_CLIENT_ID` (copy it from `GoogleService-Info.plist`).
2. Run `xcodegen generate` in the repo folder, then open `LittleLog.xcodeproj`.
3. Plug in your iPhone, pick it at the top of Xcode, and press Run. The first build downloads Firebase and takes a few minutes.

Run `xcodegen generate` again whenever you pull new code.

### 5. Share it with your family (TestFlight)

1. At [appstoreconnect.apple.com](https://appstoreconnect.apple.com) > Apps > **+** > New App, choose the `com.drzaff.littlelog` bundle ID.
2. In Xcode: choose **Any iOS Device**, then Product > **Archive** > Distribute App > TestFlight & App Store.
3. In App Store Connect > TestFlight, add your partner and other caregivers as testers (Internal testing for people on your developer team, External testing for anyone by email).
4. In the app, open **Family** > **Invite a caregiver** and enter the Google email each person will sign in with.

## How sharing works

Each baby has a list of caregiver emails. Anyone signed in with one of those Google accounts can see and edit everything for that baby. The Firestore and Storage rules in `firebase/` enforce this on the server. When someone adds or edits an entry or shares a photo, `firebase/functions/index.js` sends a notification to every other caregiver's devices.

## Project layout

```
LittleLog/
  App/         app entry, push setup, root navigation
  Models/      Baby, LogEntry, BabyPhoto, units, daily totals
  Services/    sign-in, Firestore and Storage access
  Views/       Today, Trends, Photos, Family and the logging forms
firebase/      security rules and the notification Cloud Function
project.yml    XcodeGen project definition
```

Every push is built on a Mac by GitHub Actions (`.github/workflows/ios-build.yml`) to catch compile errors.
