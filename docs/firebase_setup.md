# Firebase Setup for Majika

Majika now uses Firebase Auth, Firestore, and a callable Cloud Function so the Steam Web API key stays server-side.

## 1. Enable Firebase products

In the Firebase Console for your project:

1. Enable **Authentication** and add the **Email/Password** sign-in provider.
2. Enable **Cloud Firestore** in production mode.
3. Enable **Cloud Functions**. The `steamApi` function uses Node.js 20 and the `us-central1` region.

## 2. Firebase project connection

If you are using the Nix dev shell, enter it first:

```sh
nix develop
```

The shell makes `flutterfire`, `firebase`, Node.js 20, Flutter, and Android tooling available. On first entry it may install `flutterfire_cli` into your Dart pub cache and `firebase-tools` into `.dart_tool/npm-global`.

This repo is connected to the Firebase project `majika-ai-recommendation` through `.firebaserc`, `firebase.json`, `lib/firebase_options.dart`, and `android/app/google-services.json`.

If you need to regenerate the Firebase app config, run:

```sh
firebase login
flutterfire configure \
  --project=majika-ai-recommendation \
  --platforms=android,ios,macos,web,windows \
  --android-package-name=de.khonager.majika \
  --ios-bundle-id=de.khonager.majika \
  --macos-bundle-id=de.khonager.majika \
  --out=lib/firebase_options.dart \
  --android-out=android/app/google-services.json \
  --yes \
  --overwrite-firebase-options
```

FlutterFire currently generates config for Android, iOS, macOS, web, and Windows in this project. Linux runs with Firebase disabled unless the FlutterFire CLI adds Linux support later.

## 3. Store the Steam key as a Functions secret

From the repo root:

```sh
firebase use majika-ai-recommendation
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
