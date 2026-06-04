# ESP32 Buzzer Setup & Communication Guide

## Part 1: Buzzer Hardware Connection

### Components Needed:
- **Buzzer Module** (Active or Passive piezo buzzer)
- **470Ω - 1kΩ Resistor** (for protection, optional but recommended)
- **NPN Transistor** (2N2222 or BC547) - if using high-power buzzer
- **Diode 1N4007** (if using inductive buzzer)
- **Breadboard & Jumper wires**

### Simple Connection (Active Buzzer - Recommended):

```
ESP32 GPIO 27 ──[470Ω Resistor]──┬─→ Buzzer(+)
                                  │
                            Buzzer(-)
                                  │
                    ESP32 GND ─────┴─→ Buzzer(-)
```

**Pinout:**
- **GPIO 27** → Buzzer positive (through resistor)
- **GND** → Buzzer negative
- **Resistor** → 470Ω - 1kΩ (limits current, prevents ESP32 damage)

### Advanced Connection (Passive Buzzer with Transistor):

```
                    ┌─────────────┐
ESP32 GPIO 27 ──────┤ Base (B)    │
                    │ 2N2222/BC547│
                 ┌──┤ Collector(C)│
                 │  │             │
              +5V ├──┤ Emitter(E) ├─ GND
                 │  └─────────────┘
                 │
            Buzzer(+)
                 │
            Buzzer(-)
                 │
                GND
```

## Part 2: Communication Flow

### Data Path:
```
Flutter App (Commuter)
    ↓
Firebase RTDB: /devices/esp01/buzzer
    ↓
ESP32 (Arduino)
    ↓
GPIO 27 (Buzzer) → Activates for 5 seconds
```

### Step-by-Step Workflow:

1. **Commuter clicks "Request Ride"** in Flutter app
2. **Flutter writes to RTDB:**
   ```
   Path: /devices/esp01/buzzer
   Data: {
     "action": "buzz",
     "duration": 5000,
     "triggeredAt": "2026-06-04T10:30:45Z"
   }
   ```
3. **ESP32 streams this path** and receives the update
4. **Arduino code calls `activateBuzzerForDuration(5000)`**
5. **Buzzer activates for exactly 5 seconds then auto-stops**

## Part 3: Firebase Configuration

### RTDB URL (for Arduino):
```
https://jeepneyauth.firebaseio.com
```
**NOT** the Firestore URL!

### Database Rules (database.rules.json):
```json
{
  "rules": {
    "devices": {
      "$deviceId": {
        ".read": true,
        ".write": "auth != null",
        "buzzer": {
          ".read": true,
          ".write": "auth != null"
        }
      }
    }
  }
}
```

## Part 4: Deploy & Verify

### 1. Deploy Database Rules:
```bash
firebase deploy --only database
```

### 2. Update Arduino Code:
Ensure your Arduino code has:
```cpp
#define DATABASE_URL "https://jeepneyauth.firebaseio.com"
```

### 3. Upload Arduino Sketch

### 4. Test from Flutter:
- Make sure ESP32 is connected to WiFi
- Open Flutter app and log in
- Click "Request Ride"
- Check ESP32 Serial Monitor for: `"Buzzer activated for 5000 ms"`
- Listen for 5-second buzz from GPIO 27

## Part 5: Debugging

### Check Serial Monitor (Arduino):
```
[INFO] Streaming /devices/esp01/buzzer
[DEBUG] Firebase buzz command: duration=5000 ms
Buzzer activated for 5000 ms
```

### Check Flutter Logs:
```
[DEBUG] Buzzer command sent to ESP32
```

### Verify RTDB Path:
Go to Firebase Console → Realtime Database → Check `/devices/esp01/buzzer` exists

## Part 6: GPIO Reference for ESP32 DevKit V1

Your configured pins:
- **GPIO 27** → Buzzer (OUTPUT)
- **GPIO 22** → LED_PIN_1 (OUTPUT)
- **GPIO 21** → LED_PIN_2 (OUTPUT)
- **GPIO 18** → LED_PIN_3 (OUTPUT)
- **GPIO 23** → BTN_PIN_1 (INPUT_PULLUP) - Factory Reset
- **GPIO 19** → BTN_PIN_2 (INPUT_PULLUP) - Toggle Buzzer
- **GPIO 5** → BTN_PIN_3 (INPUT_PULLUP) - Test 5s Buzz

All pins are safe to use on ESP32 DevKit V1 ✓

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Buzzer won't activate | Check GPIO 27 connection, verify Firebase rules allow write |
| Buzzer stays on | Ensure Arduino has latest code with `updateBuzzer()` in loop |
| No Firebase connection | Verify WiFi SSID/password, check API_KEY, test with web browser first |
| Random activations | Check for floating pin, add debounce delay |
| Weak buzzer sound | Increase resistor value to 220Ω or use transistor circuit |
