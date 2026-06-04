# Buzzer Hardware Connection Guide

## Simple Setup (RECOMMENDED - Active Buzzer)

This is the easiest and safest option for beginners.

### Components:
- ESP32 DevKit V1
- **Active Piezo Buzzer** (5V or 3.3V)
- 470Ω resistor (optional but recommended)
- Breadboard & jumper wires

### Wiring Diagram (Text Format):

```
ESP32 PIN 27 ─[470Ω Resistor]─ │
                                 ├─ Buzzer(+) positive
                            GND ─┤
                                 └─ Buzzer(-) negative
                            
                          ESP32 GND
```

### Step-by-Step Connection:

1. **Get your active buzzer** - Check it has (+) and (-) markings
   
2. **Insert into breadboard:**
   ```
   Breadboard Layout:
   
   Column A (Left)        Column B (Right)
   
   Row 1: GND (rail)                      
   Row 2: GPIO27 ─────────────────────── Positive side
   Row 3: [470Ω resistor here]
   Row 4: GND (rail) ─────────────────── Negative side
   ```

3. **Connect jumper wires:**
   - ESP32 GPIO 27 → Breadboard column (with resistor)
   - Resistor other end → Buzzer positive pin (+)
   - Buzzer negative pin (-) → Breadboard GND rail
   - Breadboard GND rail → ESP32 GND pin

### Testing Connection:

Before uploading code, test with a battery:
```
3V Battery (+) → Buzzer(+)
3V Battery (-) → Buzzer(-)
→ Should hear a buzz sound
```

If no sound: Try reversing the buzzer pins (for passive buzzers)

---

## Advanced Setup (Passive Buzzer with Transistor)

Use this if you need **louder volume** or have a **passive piezo buzzer**.

### Components:
- ESP32 DevKit V1
- **Passive Piezo Buzzer** (requires AC signal)
- NPN Transistor: 2N2222, BC547, or similar
- 1kΩ Resistor (base resistor)
- 1N4007 Diode (optional, for inductive protection)
- Breadboard & jumper wires

### Wiring Diagram:

```
                    ┌──────────────────────┐
                    │   2N2222/BC547       │
                    │  Transistor          │
                    │                      │
    GPIO 27 ───────[1k Ω]──→ Base(B)       │
                    │                      │
                +5V ├──────→ Collector(C)──┤───→ Buzzer(+)
                    │                      │
                GND ├──────→ Emitter(E) ───┤───→ Buzzer(-)
                    │                      │
                    │   + │                │  (Optional Diode
                    │  ──┴──               │   across buzzer)
                    │   - │                │
                    └──────────────────────┘
```

### Breadboard Layout:

```
        A   B   C   D
    1   -   -   -   -   (GND rail)
    2   P27 |   1k  |
    3       |   R   |
    4   +5V |   +5V B (Base)
    5       |   |   C (Col)
    6   GND |   |   E (Emitter)
    7       |   GND |
    8       |   +   - (Buzzer)
    9       +-|-+---+
    10      Transistor
```

---

## Pinout Reference: ESP32 DevKit V1

```
USB
 ↓
┌─────────────────────────┐
│  ESP32 DevKit V1        │
│                         │
│ LEFT SIDE:              │ RIGHT SIDE:
│  GND                    │  3V3
│  IO23  BTN_PIN_1        │  EN
│  IO22  LED_PIN_1        │  IO36
│  IO19  BTN_PIN_2        │  IO39
│  IO21  LED_PIN_2        │  IO34
│  IO18  LED_PIN_3        │  IO35
│  IO5   BTN_PIN_3        │  IO32
│  IO17                   │  IO33
│  IO16                   │  IO25
│  IO4                    │  IO26
│  IO0                    │  IO27 ← BUZZER
│  IO2                    │  IO14
│  IO15                   │  IO12
│  D2  SD                 │  IO13
│  D3  SD                 │  IO9  SD
│  CMD SD                 │  IO10 SD
│  CLK SD                 │  IO11 SD
│ GND                     │ GND
│ 5V  (USB Power)         │ 5V (USB Power)
│                         │
└─────────────────────────┘
```

### Your GPIO Configuration:

| Function | GPIO | Type | Purpose |
|----------|------|------|---------|
| Buzzer | 27 | OUTPUT | 5-sec buzz on ride request |
| LED 1 | 22 | OUTPUT | Status indicator (blink) |
| LED 2 | 21 | OUTPUT | WiFi connected indicator |
| LED 3 | 18 | OUTPUT | Firebase ready indicator |
| Button 1 | 23 | INPUT_PULLUP | Factory reset (8s hold) |
| Button 2 | 19 | INPUT_PULLUP | Toggle buzzer manual |
| Button 3 | 5 | INPUT_PULLUP | Test 5s buzz |

---

## Buzzer Selection Guide

### Active Buzzer (Recommended ✓)

**What it is:** Has internal oscillator, generates sound with DC voltage

**Pros:**
- Simple DC connection
- Just apply voltage = sound
- No special circuitry needed
- Lower power consumption

**Cons:**
- Only one frequency
- Usually cheaper quality

**Voltage:** 3.3V or 5V DC  
**Current:** 20-30mA @ 5V
**Cost:** $1-3

**Buy:** Search "Active Piezo Buzzer 5V Arduino"

### Passive Buzzer

**What it is:** No oscillator, needs AC signal to generate sound

**Pros:**
- Adjustable frequency/tone
- Better sound quality
- Smaller size

**Cons:**
- Requires transistor circuit
- More complex wiring
- Higher power consumption

**Voltage:** 5V-20V (depends on model)  
**Current:** 50-100mA @ 5V
**Cost:** $2-5

**Buy:** Search "Passive Piezo Buzzer 5V"

---

## Power Consumption Reference

```
Component               Current Draw
─────────────────────────────────────
ESP32 (idle)           ~80mA
WiFi connected         ~140mA  
Active Buzzer (on)     ~30mA
Passive Buzzer (on)    ~80mA
3x LEDs (all on)       ~60mA
3x Buttons             ~0mA (pull-up)
─────────────────────────────────────
TOTAL (all on)         ~260mA from USB 5V
```

**Recommendation:** Use USB power supply rated for at least 500mA

---

## Testing Your Circuit

### Test 1: Buzzer with Battery (Before Code)
```
Connect directly:
Battery(+) → Buzzer(+)
Battery(-) → Buzzer(-)
→ Should hear buzz
```

### Test 2: LED Indicator Test
```
Push GPIO 5 button
→ All 3 LEDs should flash
→ Serial Monitor shows: [BTN3] Manual 5-second buzzer test
→ Buzzer should buzz for 5 seconds
```

### Test 3: Full App Integration
```
1. Upload Arduino code
2. Run Flutter app
3. Log in as commuter
4. Click "Request Ride"
5. Listen for 5-second buzz
6. Check Serial Monitor for: [FIREBASE] Buzz command
```

---

## Common Issues & Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| No sound from buzzer | Wrong polarity | Try reversing (+/-) |
| Weak/quiet buzzer | Using 3.3V, need 5V | Use transistor circuit or 5V supply |
| Buzzer won't turn off | Code issue, not hardware | Check `updateBuzzer()` called in loop |
| ESP32 resets on buzzer | Power surge | Add 470Ω resistor in series |
| Button pressed but no response | Pin not pulled up | Check `INPUT_PULLUP` in code |
| Intermittent buzzer | Loose wiring | Check breadboard connections |

---

## Shopping List

### Minimum (Active Buzzer):
- [ ] Active Piezo Buzzer 5V - $2
- [ ] 470Ω Resistor pack - $1
- [ ] Breadboard - $2
- [ ] Jumper wires pack - $3
- [ ] **Total: ~$8**

### Complete (with LEDs & Buttons):
- [ ] Active Piezo Buzzer 5V - $2
- [ ] 3x 5mm LED (red, green, blue) - $2
- [ ] 3x Momentary buttons - $2
- [ ] Resistor pack (various values) - $2
- [ ] Breadboard - $3
- [ ] Jumper wires pack - $3
- [ ] **Total: ~$14**

---

## Verification Checklist

Before deploying to production:

- [ ] Buzzer sounds on Button 3 press
- [ ] Buzzer stops after 5 seconds automatically
- [ ] LEDs show WiFi status correctly
- [ ] Firebase RTDB path shows buzzer data
- [ ] Flutter app triggers buzzer when requesting ride
- [ ] Serial Monitor shows no error messages
- [ ] All 3 buttons respond to presses
- [ ] Factory reset (Button 1, 8s hold) works
