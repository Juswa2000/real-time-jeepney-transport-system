# ESP32 ↔ Flutter App Communication Setup

## ✓ Status Checklist

Before testing, ensure you have completed:

- [ ] Downloaded the corrected `esp32-provision-buzzer.ino`
- [ ] Updated `lib/screens/commuter_page.dart` with buzzer trigger
- [ ] Firebase Database Rules deployed
- [ ] Firebase Console configured

---

## Step 1: Deploy Firebase Database Rules

### Option A: Using Firebase CLI

```bash
# Install Firebase CLI if needed
npm install -g firebase-tools

# Login to Firebase
firebase login

# Deploy database rules
firebase deploy --only database
```

**Output should show:**
```
✓  database: rules updated successfully
```

### Option B: Manual Setup via Console

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select **jeepneyauth** project
3. Go to **Realtime Database** → **Rules** tab
4. Copy-paste content from `database.rules.json`
5. Click **Publish**

---

## Step 2: Configure Arduino IDE

1. **Install ESP32 Board:**
   - Arduino IDE → Preferences → Additional Boards Manager URLs
   - Add: `https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json`
   - Tools → Board → Boards Manager → Search "ESP32" → Install

2. **Install Firebase ESP32 Library:**
   - Sketch → Include Library → Manage Libraries
   - Search "Firebase ESP32"
   - Install by **Mobizt**

3. **Select Board:**
   - Tools → Board → **ESP32 Dev Module** (or your variant)
   - Tools → Port → Select your COM port

---

## Step 3: Upload Arduino Code

1. Open `esp32-provision-buzzer.ino` in Arduino IDE
2. Verify code compiles: **Sketch → Verify**
3. Upload to ESP32: **Sketch → Upload**

**Expected Serial Output:**
```
[SYSTEM] Starting ESP32 Buzzer System...
[CONFIG] Device ID: esp01
[WIFI] Connecting to: SmartSakay
.
[WIFI] ✓ Connected: 192.168.1.X
[FIREBASE] Firebase initialized
[FIREBASE] ✓ Streaming: /devices/esp01/buzzer
[SYSTEM] Setup complete. Ready for commands!
```

---

## Step 4: Configure Flutter App

1. **Firebase Database Import:**
   ```dart
   import 'package:firebase_database/firebase_database.dart';
   ```
   ✓ Already added in `commuter_page.dart`

2. **Buzzer Trigger Function:**
   ```dart
   Future<void> _triggerBuzzer() async {
     try {
       final dbRef = FirebaseDatabase.instance.ref('devices/esp01/buzzer');
       await dbRef.set({
         'action': 'buzz',
         'duration': 5000,
         'triggeredAt': DateTime.now().toIso8601String(),
       });
       print('[DEBUG] Buzzer command sent to ESP32');
     } catch (e) {
       print('[DEBUG] Failed to trigger buzzer: $e');
     }
   }
   ```
   ✓ Already added in `commuter_page.dart`

3. **Called from _requestRide():**
   ```dart
   await _triggerBuzzer();  // Sends buzz command to ESP32
   ```
   ✓ Already integrated in `commuter_page.dart`

---

## Step 5: Test the Connection

### Test 1: Local GPIO Button (No App)

1. ESP32 is running and connected to WiFi
2. **Press GPIO 5 button** on ESP32 for 3+ seconds
3. Listen for 5-second buzz from buzzer on GPIO 27
4. Check Serial Monitor for: `[BTN3] Manual 5-second buzzer test activated`

**Status:** ✓ Local button works → GPIO circuit is correct

### Test 2: Firebase RTDB Manual Write

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select **jeepneyauth** project
3. Go to **Realtime Database**
4. Look for path: `/devices/esp01/buzzer`
5. Manually write data:
   ```json
   {
     "action": "buzz",
     "duration": 5000,
     "timestamp": "2026-06-04T10:00:00Z"
   }
   ```
6. Click **Set** or **Update**
7. Check ESP32 Serial Monitor for: `[FIREBASE] Buzz command received: duration=5000 ms`
8. Listen for buzzer buzz

**Status:** ✓ Firebase streaming works → ESP32 is listening correctly

### Test 3: Full App-to-ESP32 Communication

1. **Start Flutter app:**
   ```bash
   flutter run
   ```

2. **Login as Commuter**

3. **Request a Ride** (click the ride request button)

4. **Check Flutter Console:**
   ```
   [DEBUG] Buzzer command sent to ESP32
   ```

5. **Check Arduino Serial Monitor:**
   ```
   [FIREBASE] Buzz command received: duration=5000 ms
   [BUZZER] Activated for 5000 ms
   [BUZZER] Timeout after 5000 ms
   ```

6. **Listen for Buzzer:** Should buzz for exactly 5 seconds

**Status:** ✓ Complete end-to-end communication working!

---

## Troubleshooting

### Issue: ESP32 doesn't connect to WiFi

**Solution:**
- Check WiFi name (SSID) is correct
- Check password is correct
- Restart ESP32
- Check WiFi router is 2.4GHz (ESP32 doesn't support 5GHz)

### Issue: Firebase not streaming

**Solution:**
- Check API_KEY is correct
- Check DATABASE_URL is `https://jeepneyauth.firebaseio.com`
- Verify database rules are deployed
- Check Firebase console shows data under `/devices/esp01`

### Issue: Buzzer doesn't activate

**Solution:**
- Verify GPIO 27 buzzer is properly connected
- Check power supply to ESP32 (5V USB or 3.3V pin)
- Test with Button 3 (GPIO 5) first
- Try with buzzer directly to 3.3V (test circuit)
- Check if buzzer is active (polarity matters on non-active buzzers)

### Issue: Buzzer stays on

**Solution:**
- Update Arduino code to include `updateBuzzer()` in `loop()`
- Verify `buzzerTimingEnabled` is working
- Check `millis()` overflow handling

### Issue: Flutter app can't write to RTDB

**Solution:**
- Check database rules are deployed (use `firebase deploy --only database`)
- Verify user is authenticated (logged in)
- Check user has write permission to `/devices/esp01/buzzer`
- Verify Firebase imports: `import 'package:firebase_database/firebase_database.dart';`

---

## Files Reference

| File | Purpose |
|------|---------|
| `esp32-provision-buzzer.ino` | Arduino sketch for ESP32 |
| `database.rules.json` | Firebase RTDB security rules |
| `firebase.json` | Firebase deployment config |
| `lib/screens/commuter_page.dart` | Flutter commuter app with buzzer trigger |
| `ESP32_BUZZER_SETUP.md` | Hardware connection guide |

---

## Quick Reference Commands

```bash
# Deploy all Firebase rules
firebase deploy

# Deploy only database rules
firebase deploy --only database

# Deploy only Firestore rules
firebase deploy --only firestore

# Run Flutter app
flutter run

# Monitor Android logs
flutter logs

# Monitor Serial output (Arduino IDE)
Tools → Serial Monitor (9600 baud for ESP32)
```

---

## Success Indicators

✓ **All systems working when:**
1. ESP32 shows `[SYSTEM] Setup complete. Ready for commands!`
2. Firebase Console shows data in `/devices/esp01/buzzer`
3. Flutter app shows `[DEBUG] Buzzer command sent to ESP32`
4. Buzzer buzzes for exactly 5 seconds
5. No error messages in logs

