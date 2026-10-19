# Little Log

A shared baby tracker for iPhone with a cute jungle theme. Everyone who cares for the baby signs in with Google, logs feeds, sleep, diapers, growth, milestones, daycare drop-offs and photos, and gets a notification when someone else logs something.

## What it does

- **Today**: a daily report (feeds, breast time per side, bottle and pumped amounts, wet and dirty diapers, daycare times, weight), "last feed", "next side" and "last diaper" at a glance, one-tap logging, and a timeline you can scroll back day by day. Tap any entry to edit it, swipe to delete.
- **Feeds**: breastfeeding with a left/right timer, bottle (formula or breast milk), pumping with per-side timers and amount, or any combination in one entry.
- **Sleep**: start a sleep and tap Wake up later, or log one after the fact.
- **Diapers**: pee, poop or both, with optional stool color and consistency.
- **Growth**: weight, length and head size, with WHO percentiles (set boy or girl in the profile).
- **Milestones** (with confetti), **daycare** drop-off and pick-up, and one-tap **repeat last bottle**.
- **Trends**: week and month charts by day, a year view by month (daily averages), and a growth chart over the WHO percentile curves. **Doctor report** makes a PDF to share or print.
- **Siri**: "Log a diaper in Little Log", "Log a bottle in Little Log", "Start a nap in Little Log", "Baby woke up in Little Log", "When was the last feed in Little Log".
- **Widget and Live Activities**: last feed, next side and last diaper on the home or lock screen; running feed timers and sleep on the lock screen and in the Dynamic Island.
- **Feed reminders**: notify everyone when it's been a set number of hours since the last feed (Family > Settings).
- **Photos**: share photos with the family, add captions, save or share them.
- **Family**: several babies, invite caregivers by their Google email, units (oz/lb or ml/kg).

Built with SwiftUI, Swift Charts and Firebase (Google sign-in, Firestore, Storage, push notifications through Cloud Functions).

## Set up (one time, no Mac needed)

Everything below happens in a web browser. A cloud Mac on GitHub builds the app and sends it to TestFlight, Apple's free app for installing test builds. You need:

- an **Apple Developer Program** membership ($99/year): [enroll here](https://developer.apple.com/programs/enroll) with the Apple Account on your iPhone,
- a Google account for **Firebase**.

The bundle ID used below is `com.drzaff.littlelog`. Use the same one everywhere.

### 1. Firebase

1. At [console.firebase.google.com](https://console.firebase.google.com), create a project. Google Analytics can stay off.
2. Click **Upgrade** (bottom left) and choose the **Blaze** plan. Photo storage and notifications require it, and a family's usage stays in the free allowance. Set a budget alert of a few dollars.
3. **Build > Authentication > Get started > Google > Enable**, then Save.
4. **Build > Firestore Database > Create database**, production mode, a location near you.
5. **Build > Storage > Get started**, production mode, the same location.
6. Gear icon > **Project settings > General > Add app > iOS**. Bundle ID `com.drzaff.littlelog`, nickname "Little Log". Download **GoogleService-Info.plist** and skip the remaining wizard steps. Put the file in the `LittleLog/` folder of this repo (or hand it to Claude to commit).

### 2. Deploy the security rules and notification function (Google Cloud Shell)

1. On this repo's GitHub page, click **Code > Download ZIP**.
2. Open [console.cloud.google.com](https://console.cloud.google.com), pick your Firebase project at the top, and click the **Cloud Shell** icon (`>_`, top right).
3. In Cloud Shell, open the **⋮** menu > **Upload** and choose the ZIP.
4. Paste these lines, replacing `YOUR-PROJECT-ID` with your project ID (shown under the project name in Firebase, like `little-log-be12c`):

   ```sh
   unzip -oq baby-tracker-main.zip && cd baby-tracker-main/firebase
   (cd functions && npm install --no-audit --no-fund)
   firebase login --no-localhost
   firebase deploy --project YOUR-PROJECT-ID
   ```

   `firebase login` shows a link. Open it, sign in, and paste the code back. If deploy asks to grant Storage a role for cross-service rules, answer **Y**.

Repeat this step whenever the files in `firebase/` change (feed reminders were added later, so if you deployed before them, run it again). If it asks to enable Cloud Scheduler, answer **Y**.

### 3. Apple: app ID, push key and app record

1. **App ID**: [developer.apple.com > Identifiers](https://developer.apple.com/account/resources/identifiers/list) > **+** > App IDs > App. Description "Little Log", Bundle ID **Explicit** `com.drzaff.littlelog`, tick **Push Notifications**, then Register.
2. **Push key**: [Keys](https://developer.apple.com/account/resources/authkeys/list) > **+**, name it "Little Log push", tick **Apple Push Notifications service (APNs)**, Continue, Register, **Download** the `.p8` file (you can only download it once). Note the **Key ID**.
3. In Firebase: **Project settings > Cloud Messaging > Apple app configuration > APNs Authentication Key > Upload**. Choose that `.p8` file and enter its Key ID and your **Team ID** (shown at [developer.apple.com > Membership details](https://developer.apple.com/account#MembershipDetailsCard)).
4. **App record**: [appstoreconnect.apple.com](https://appstoreconnect.apple.com) > Apps > **+ > New App**. Platform iOS, name "Little Log" (if it's taken, add a word, since only the store listing uses it), bundle ID `com.drzaff.littlelog`, SKU `littlelog`, Full Access.

### 4. Connect GitHub to Apple

1. In App Store Connect: **Users and Access > Integrations > App Store Connect API**. Request access if asked, then under **Team Keys** click **+**. Name it "GitHub", Access **Admin**, Generate.
2. Note the **Issuer ID** (above the table) and the key's **Key ID**, then **Download** the `.p8` file (only possible once).
3. On this repo on GitHub: **Settings > Secrets and variables > Actions > New repository secret**. Add four secrets:

   | Name | Value |
   |---|---|
   | `APP_STORE_CONNECT_ISSUER_ID` | the Issuer ID |
   | `APP_STORE_CONNECT_KEY_ID` | the Key ID |
   | `APP_STORE_CONNECT_KEY` | open the `.p8` file in Notepad and paste all of it, including the BEGIN/END lines |
   | `APPLE_TEAM_ID` | your Team ID |

These keys stay in GitHub's encrypted secrets. Don't paste them into chats or commit them.

### 5. Build and send to TestFlight

1. On GitHub: **Actions > Send to TestFlight > Run workflow**. It takes about 15 minutes.
2. In App Store Connect > your app > **TestFlight**, the build appears after Apple finishes processing it (usually 10 to 30 minutes).
3. Under **Internal Testing**, create a group and add testers. Testers must first be added as users in **Users and Access** (any role works, for example "Customer Support"). Add yourself and your partner.
4. Each tester installs **TestFlight** from the App Store, opens the email invite and taps Install.

To ship a new version later, run the workflow again. TestFlight builds expire after 90 days, so run it at least that often.

### 6. Start using it

Open Little Log, sign in with Google, add your baby, then go to **Family > Invite a caregiver** and enter the Google email each person signs in with.

### Optional: build on a Mac

With a Mac, fill in `Config.xcconfig`, run `brew install xcodegen && xcodegen generate`, open `LittleLog.xcodeproj` and press Run.

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
scripts/       creates signing certificates from the App Store Connect API key
project.yml    XcodeGen project definition
```

GitHub Actions compiles every pull request on a cloud Mac (`ios-build.yml`) and builds TestFlight releases on demand (`testflight.yml`). Private repos get a limited number of free cloud Mac minutes each month (roughly a dozen TestFlight builds), so the workflows don't run on every push.
