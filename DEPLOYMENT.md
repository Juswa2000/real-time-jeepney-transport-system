# Flutter Admin Dashboard Deployment Guide

This guide is for deploying your Flutter admin dashboard as a public web app using Firebase Hosting, Firebase Authentication, and Cloud Firestore.

## What is already configured
- `firebase.json` - hosting configuration
- `.firebaserc` - Firebase project selection
- `firestore.rules` - Firestore access rules for authenticated users and admins
- Flutter web support is available via `web/`
- `firebase_options.dart` is already set for project `jeepneyauth`

## Local steps you do in this repo

### 1. Install dependencies
```bash
flutter pub get
```

### 2. Build the Flutter web app
```bash
flutter clean
flutter build web --release
```

### 3. Deploy to Firebase Hosting
```bash
firebase deploy --only hosting
```

If you need to target a specific Firebase project explicitly:
```bash
firebase deploy --only hosting --project=jeepneyauth
```

### 4. Test the deployed URL
After deployment, open:
```text
https://jeepneyauth.web.app
```

## What to do in Firebase Console (outside this repo)

### A. Enable Firebase Authentication
1. Open Firebase Console
2. Go to `Authentication` → `Sign-in method`
3. Enable `Email/Password`

### B. Create admin user accounts
1. Go to `Authentication` → `Users`
2. Click `Add user`
3. Enter admin email and password

### C. Create user records in Firestore
1. Go to `Firestore Database`
2. Open the `users` collection
3. Add a document with the same UID as the admin user
4. Create these fields:
   - `email`: admin user email
   - `name`: admin name
   - `role`: `admin`

Example Firestore document path:
```text
users/<admin-uid>
```
Example document data:
```json
{
  "email": "admin@example.com",
  "name": "Admin User",
  "role": "admin"
}
```

### D. (Optional) Create Firestore collections used by the dashboard
The admin dashboard reads from these collections:
- `drivers`
- `commuters`
- `notifications`
- `reports`

You can seed documents manually for testing, or populate them from your app logic.

### E. Confirm Firestore rules
The `firestore.rules` file in this repo already allows:
- authenticated users to read `drivers`, `commuters`, `notifications`, and `reports`
- only admins to write to `notifications` and `reports`
- users to read/write their own `users` documents

If you update rules from the console, make sure they still allow authenticated admin users to read these collections.

## Admin dashboard access flow
1. Open the hosted URL in a browser
2. Sign in with a Firebase-authenticated user
3. The app checks the Firestore `users/<uid>.role`
4. If the role is `admin`, the dashboard opens

## What I changed for you
- Added `firebase.json` for Firebase Hosting
- Added `.firebaserc` for project selection
- Added Firestore rules for admin and authenticated data access
- Updated the login screen text to recommend Firebase admin credentials

## Troubleshooting

### If deployment fails
- Run `firebase login`
- Make sure `firebase use` points to `jeepneyauth`
- Confirm `build/web` exists before deploy

### If the dashboard loads but data is blank
- Confirm you are signed in
- Confirm your user has a `users/<uid>` Firestore document with `role: admin`
- Confirm `drivers`, `commuters`, `notifications`, and `reports` exist or are readable

### If you see `Unable to determine your role`
- Open Firestore and verify the signed-in user's `role` field is present
- If missing or empty, add `role: admin` to the user document

## External tasks for you to do
- Enable Firebase Authentication Email/Password
- Create admin users in Firebase Auth
- Create matching `users` documents in Firestore with `role: admin`
- Deploy with `firebase deploy --only hosting`

Once those external Firebase setup steps are complete, panelists can access the dashboard using:
```text
https://jeepneyauth.web.app
```
