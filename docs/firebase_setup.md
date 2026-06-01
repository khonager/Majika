# Firebase Setup for Majika

Majika now uses Firebase Auth, Firestore, and a callable Cloud Function so the Steam Web API key stays server-side.

## 1. Enable Firebase products

In the Firebase Console for your project:

1. Enable **Authentication** and add the **Email/Password** sign-in provider.
2. Enable **Cloud Firestore** in production mode.
3. Enable **Cloud Functions**. The `steamApi` function uses Node.js 20 and the `us-central1` region.

## 2. Connect the Flutter app

Recommended path:

```sh
dart pub global activate flutterfire_cli
firebase login
flutterfire configure
```

Choose your existing Firebase project and the platforms you want to build. If you let FlutterFire overwrite `lib/firebase_options.dart`, keep the class name `DefaultFirebaseOptions`; the app already imports it.

Alternative path without FlutterFire:

```sh
flutter run \
  --dart-define=FIREBASE_PROJECT_ID=your-project-id \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=1234567890 \
  --dart-define=FIREBASE_STORAGE_BUCKET=your-project-id.appspot.com \
  --dart-define=FIREBASE_ANDROID_API_KEY=... \
  --dart-define=FIREBASE_ANDROID_APP_ID=...
```

Use the matching `FIREBASE_WEB_*`, `FIREBASE_IOS_*`, `FIREBASE_MACOS_*`, `FIREBASE_WINDOWS_*`, or `FIREBASE_LINUX_*` values for other platforms.

## 3. Store the Steam key as a Functions secret

From the repo root:

```sh
firebase use your-project-id
firebase functions:secrets:set STEAM_WEB_API_KEY
```

Paste your Steam Web API key when prompted. Do not put this key in Flutter, `.env`, or `--dart-define`.

## 4. Deploy backend pieces

```sh
cd functions
npm install
npm run lint
cd ..
firebase deploy --only functions,firestore:rules
```

## 5. Run the app

Start the app, open **Profile**, create an email/password account, then import Steam from the home screen. Steam profiles must have public library visibility for owned games to import.
