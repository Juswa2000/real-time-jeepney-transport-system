Testing Realtime Driver Location (Commuter + Driver)

Quick checklist
- Ensure Firebase project configured and `google-services.json` (Android) / `GoogleService-Info.plist` (iOS) present in `app/`.
- Enable Firestore in the Firebase Console and deploy `firestore.rules` from project root.
- Have two devices/emulators or one device + emulator: one signed in as a driver, another as commuter.

Android permissions (recommended)
- In `android/app/src/main/AndroidManifest.xml` add:
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
  <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
  <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
- For Android 12+ also declare approximate/precise location handling in runtime code (app already requests via Geolocator).

iOS permissions (recommended)
- In `ios/Runner/Info.plist` add keys:
  - `NSLocationWhenInUseUsageDescription` (reason string)
  - `NSLocationAlwaysAndWhenInUseUsageDescription` (reason string)
  - `UIBackgroundModes` include `location` if you need background updates.

Run locally
- Fetch packages:
```
flutter pub get
```
- Start a driver instance and enable live publishing from the Driver Dashboard (tap "Start Live Publish").
- Start a commuter instance and open the Commuter Dashboard — markers should appear and move smoothly.

Debugging tips
- Use `flutter logs` or Android Studio Logcat to see background publishing errors.
- Verify Firestore writes by inspecting the `drivers` collection in Firebase Console.
- If markers don't appear, ensure `gpsEnabled`, `latitude`, and `longitude` fields are present on the driver's document.

Security
- `firestore.rules` in project root limits writes so drivers can only write their own doc. Deploy with:
```
firebase deploy --only firestore:rules
```

If you'd like, I can:
- Harden Firestore rules with field validation and rate-limiting examples.
- Add example background service code for long-running Android publishing.
- Run the app on an available connected device/emulator now.
