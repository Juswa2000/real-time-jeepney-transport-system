# 🚀 ESP32 Buzzer Integration - QUICK START

## Hardware Connection (30 seconds)

```
ESP32 GPIO 27 ──[470Ω]──┬─ Buzzer(+)
                        │
                    ESP32 GND ─ Buzzer(-)
```

**Parts:** ESP32, Active buzzer 5V, 470Ω resistor, breadboard, wires

---

## Setup Steps (Total: ~1 hour)

### 1️⃣ Hardware (15 min)
```
[GPIO27] ──[Resistor]── [Buzzer+]
[GND]   ─────────────── [Buzzer-]
```
**Test:** Connect buzzer to battery → should buzz

### 2️⃣ Deploy Firebase (10 min)
```bash
firebase deploy --only database
```
✓ Verify in Firebase Console under Realtime Database → Rules

### 3️⃣ Upload Arduino (10 min)
1. Arduino IDE → Tools → Board → ESP32 Dev Module
2. Install Firebase ESP32 library (Mobizt)
3. Open `esp32-provision-buzzer.ino`
4. Sketch → Upload
5. Check Serial Monitor (9600 baud)
   - Should see: `[SYSTEM] Setup complete`

### 4️⃣ Test Locally (5 min)
```
Press GPIO 5 button → Buzzer buzzes 5 seconds → ✓
```

### 5️⃣ Test Firebase (5 min)
Firebase Console → Realtime DB → Click `/devices/esp01/buzzer`
```json
{
  "action": "buzz",
  "duration": 5000
}
```
→ Buzzer buzzes 5 seconds → ✓

### 6️⃣ Test Flutter App (10 min)
```bash
flutter run
```
Login → Click "Request Ride" → Buzzer buzzes 5 seconds → ✓

---

## Firebase Config

**Project:** jeepneyauth  
**RTDB URL:** `https://jeepneyauth.firebaseio.com`  
**Path:** `/devices/esp01/buzzer`

**Rules:** `database.rules.json` (already created)

---

## Arduino Commands (Serial Monitor)

| Command | Result |
|---------|--------|
| Button 3 press | 5-second buzz test |
| Button 1 hold 8s | Factory reset |
| Button 2 press | Manual toggle buzzer |

**Debug Output:**
```
[SYSTEM] Starting...
[WIFI] Connected: 192.168.X.X
[FIREBASE] ✓ Streaming: /devices/esp01/buzzer
[BTN3] Manual 5-second buzzer test activated
[BUZZER] Activated for 5000 ms
[BUZZER] Timeout after 5000 ms
```

---

## Flutter Integration

**File:** `lib/screens/commuter_page.dart`

**Import:** ✓ Already added
```dart
import 'package:firebase_database/firebase_database.dart';
```

**Function:** ✓ Already added
```dart
Future<void> _triggerBuzzer() async {
  final dbRef = FirebaseDatabase.instance.ref('devices/esp01/buzzer');
  await dbRef.set({
    'action': 'buzz',
    'duration': 5000,
    'triggeredAt': DateTime.now().toIso8601String(),
  });
}
```

**Called from:** `_requestRide()` ✓

---

## GPIO Pinout

| Function | GPIO | Status |
|----------|------|--------|
| Buzzer | 27 | ✓ Connected |
| LED 1 (status) | 22 | ✓ Configured |
| LED 2 (WiFi) | 21 | ✓ Configured |
| LED 3 (Firebase) | 18 | ✓ Configured |
| Button 1 (reset) | 23 | ✓ Configured |
| Button 2 (toggle) | 19 | ✓ Configured |
| Button 3 (test) | 5 | ✓ Configured |

---

## Troubleshooting in 60 Seconds

### No Buzzer Sound
1. Check GPIO 27 is connected ← START HERE
2. Test buzzer with battery directly
3. Try reversing buzzer polarity
4. Check 470Ω resistor not broken

### Firebase Not Working
1. Run `firebase deploy --only database`
2. Check WiFi connection on ESP32
3. Verify API_KEY in Arduino code
4. Check `/devices/esp01` path exists in Firebase

### Button Doesn't Work
1. Verify button pressed to GND (INPUT_PULLUP)
2. Check GPIO pin number in code
3. Test with Serial.println()

---

## Files Reference

| File | What | Where |
|------|------|-------|
| `esp32-provision-buzzer.ino` | Arduino code | Upload to ESP32 |
| `database.rules.json` | Firebase rules | Deploy with Firebase CLI |
| `lib/screens/commuter_page.dart` | Flutter code | Already updated |
| `FIREBASE_COMMUNICATION_SETUP.md` | Detailed guide | Read for full steps |
| `BUZZER_HARDWARE_GUIDE.md` | Hardware help | Read for circuit issues |

---

## Success Checklist ✓

- [ ] Buzzer connected to GPIO 27
- [ ] Firebase rules deployed
- [ ] Arduino uploaded successfully
- [ ] ESP32 shows "Setup complete" in Serial
- [ ] Button 3 test works (5-second buzz)
- [ ] Firebase manual test works
- [ ] Flutter app triggers buzzer
- [ ] All lights blink/turn on/off correctly

---

## Common Serial Monitor Messages

| Message | Meaning | Action |
|---------|---------|--------|
| `Setup complete. Ready for commands!` | ✓ Good | Ready to test |
| `Stream begin failed` | RTDB issue | Check API key, rules |
| `Control read failed` | RTDB read issue | Check database rules |
| `Activated for 5000 ms` | ✓ Buzzer on | Normal |
| `Timeout after 5000 ms` | ✓ Buzzer off | Normal |

---

## Next Action

Choose one:

1. **Get started now:** Follow steps 1-6 above
2. **Need details:** Read `COMMUNICATION_ARCHITECTURE.md`
3. **Hardware help:** Read `BUZZER_HARDWARE_GUIDE.md`
4. **Firebase help:** Read `FIREBASE_COMMUNICATION_SETUP.md`

---

## Contact/Support

If stuck:
1. Check Serial Monitor for errors
2. Review relevant documentation file
3. Verify Firebase console shows data
4. Test hardware independently (buzzer + battery)

---

**Ready?** → Start with Step 1: Hardware Connection ⚡

