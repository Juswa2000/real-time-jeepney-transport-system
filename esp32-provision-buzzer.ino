// esp32firebase.ino - REST API + SoftAP Provisioning
//   WiFi + Firebase REST API + Buzzer Control + Web Configuration

  // DRIVER ACCOUNT BINDING:
  // ─────────────────────────────
  // The ESP32 no longer writes to a fixed Firestore path.
  // Instead it reads /devices/<deviceId>/driverUid from Realtime Database.
  // The Flutter driver page writes that field when the driver logs in and
  // claims the device, and clears it on logout.

  // Flow:
  //   1. ESP32 boots → registers itself at /devices/esp01/deviceId in RTDB
  //   2. Flutter driver logs in → writes their UID to /devices/esp01/driverUid
  //   3. ESP32 polls every 5 s → detects the UID → LEDs blink 3 times
  //   4. Button presses → PATCH /drivers/<driverUid> in Firestore REST API
  //   5. Flutter driver logs out → clears /devices/esp01/driverUid
  //   6. ESP32 detects null → clears stored UID, 1 blink, waits for next login

//   FIREBASE RULES (Realtime Database):
//     { "rules": { ".read": true, ".write": true } }

#include <WiFi.h>
#include <WebServer.h>
#include <Preferences.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <ArduinoJson.h>

// ---------- EDIT THESE BEFORE UPLOAD ----------
#define DEFAULT_DEVICE_ID  "esp01"
#define SOFTAP_SSID        "ESP32-Config"
#define SOFTAP_PASSWORD    "12345678"

// Realtime Database (asia-southeast1)
#define DATABASE_URL \
  "https://jeepneyauth-default-rtdb.asia-southeast1.firebasedatabase.app"

// Firestore REST base
#define FIRESTORE_URL \
  "https://firestore.googleapis.com/v1/projects/jeepneyauth/databases/(default)/documents"

// Optional — leave "" if Firebase rules allow public read/write
#define DATABASE_SECRET ""
// ---------- END EDITABLE SECTION ----------

Preferences prefs;
WebServer   server(80);

String savedSsid = "";
String savedPass = "";

// GPIO
const int LED_PIN_1 = 22;   // FULL LED
const int LED_PIN_2 = 21;   // LIMITED LED
const int LED_PIN_3 = 18;   // AVAILABLE LED
const int BTN_PIN_1 = 23;
const int BTN_PIN_2 = 19;
const int BTN_PIN_3 = 5;
#define   BUZZER_PIN  27

// State
String deviceId       = DEFAULT_DEVICE_ID;
String driverStatus   = "AVAILABLE";
String boundDriverUid = "";
bool   wifiConnected  = false;

// ── Button edge-detection state ──────────────────────────────────────────
bool btn1State = HIGH, btn2State = HIGH, btn3State = HIGH;
bool btn1Prev  = HIGH, btn2Prev  = HIGH, btn3Prev  = HIGH;

unsigned long btn1Last = 0, btn2Last = 0, btn3Last = 0;
const unsigned long DEBOUNCE_MS = 50;

// ── Pending status (decoupled from HTTP) ─────────────────────────────────
String pendingStatus = "";
bool   statusDirty   = false;

// Buzzer
bool          buzzerActive   = false;
unsigned long buzzerStart    = 0;
unsigned long buzzerDuration = 5000;

// Polling timers
unsigned long lastBuzzerCheck = 0;
unsigned long lastUidPoll     = 0;
unsigned long lastHeartbeat   = 0;
unsigned long lastStatusPush  = 0;

const unsigned long BUZZER_CHECK_MS =   500;
const unsigned long UID_POLL_MS     =  5000;
const unsigned long HEARTBEAT_MS    = 30000;
const unsigned long STATUS_DEDUP_MS =   500;  // reduced from 1000

// ─────────────────────────── Helpers ──────────────────────────────────────

String rtdbUrl(String path) {
  String url = String(DATABASE_URL) + path + ".json";
  if (String(DATABASE_SECRET).length() > 0)
    url += "?auth=" + String(DATABASE_SECRET);
  return url;
}

WiFiClientSecure freshClient() {
  WiFiClientSecure c;
  c.setInsecure();
  return c;
}

// ─────────────────────────── LEDs ─────────────────────────────────────────

void updateLEDs() {
  digitalWrite(LED_PIN_1, driverStatus == "FULL"      ? HIGH : LOW);
  digitalWrite(LED_PIN_2, driverStatus == "LIMITED"   ? HIGH : LOW);
  digitalWrite(LED_PIN_3, driverStatus == "AVAILABLE" ? HIGH : LOW);
}

// Blink all LEDs n times — signals driver bind/unbind events
void signalBlink(int times) {
  for (int i = 0; i < times; i++) {
    digitalWrite(LED_PIN_1, HIGH);
    digitalWrite(LED_PIN_2, HIGH);
    digitalWrite(LED_PIN_3, HIGH);
    delay(150);
    digitalWrite(LED_PIN_1, LOW);
    digitalWrite(LED_PIN_2, LOW);
    digitalWrite(LED_PIN_3, LOW);
    delay(150);
  }
  updateLEDs();
}

// ─────────────────────────── Buzzer ───────────────────────────────────────

void activateBuzzer(unsigned long ms) {
  digitalWrite(BUZZER_PIN, HIGH);
  buzzerStart    = millis();
  buzzerDuration = ms;
  buzzerActive   = true;
  Serial.printf("[BUZZER] ON for %lu ms\n", ms);
}

void tickBuzzer() {
  if (buzzerActive && millis() - buzzerStart >= buzzerDuration) {
    digitalWrite(BUZZER_PIN, LOW);
    buzzerActive = false;
    Serial.println("[BUZZER] OFF");
  }
}

// ──────────────────── Status → Firestore REST ─────────────────────────────

void pushStatusToFirestore(String status, bool force) {
  if (!wifiConnected) return;
  if (boundDriverUid.length() == 0) {
    Serial.println("[STATUS] No driver bound — skip");
    return;
  }

  driverStatus   = status;
  lastStatusPush = millis();

  String color, label;
  int    seats;
  if      (status == "FULL")    { color = "red";    label = "Full";    seats = 0; }
  else if (status == "LIMITED") { color = "orange"; label = "Limited"; seats = 2; }
  else                          { color = "green";  label = "Vacant";  seats = 8; }

  String url = String(FIRESTORE_URL) + "/drivers/" + boundDriverUid
             + "?updateMask.fieldPaths=statusColor"
             + "&updateMask.fieldPaths=statusLabel"
             + "&updateMask.fieldPaths=availableSeats";

  String body = "{\"fields\":{"
    "\"statusColor\":{\"stringValue\":\"" + color + "\"},"
    "\"statusLabel\":{\"stringValue\":\"" + label + "\"},"
    "\"availableSeats\":{\"integerValue\":" + String(seats) + "}"
    "}}";

  WiFiClientSecure client = freshClient();
  HTTPClient http;
  http.setTimeout(5000);   // 5s timeout so it doesn't block forever
  http.begin(client, url);
  http.addHeader("Content-Type", "application/json");
  int code = http.PATCH(body);

  if (code == 200) {
    Serial.printf("[STATUS] OK: %s → uid=%s\n",
                  status.c_str(), boundDriverUid.c_str());
  } else {
    Serial.printf("[STATUS] FAIL HTTP %d\n", code);
    if (code == 404) Serial.println("  → driver doc missing in Firestore");
    if (code == 401) Serial.println("  → Firestore auth required (add API key)");
    if (code == -1)  Serial.println("  → SSL error / timeout");
  }
  http.end();
}

// ──────────────────── Driver UID poll (RTDB) ──────────────────────────────

String fetchDriverUid() {
  if (!wifiConnected) return boundDriverUid;

  WiFiClientSecure client = freshClient();
  HTTPClient http;
  http.setTimeout(5000);
  http.begin(client, rtdbUrl("/devices/" + deviceId + "/driverUid"));
  int code = http.GET();
  String uid = "";

  if (code == 200) {
    String raw = http.getString();
    raw.trim();
    if (raw != "null" && raw.length() > 2) {
      raw.replace("\"", "");
      uid = raw;
    }
  } else {
    Serial.printf("[UID] fetch HTTP %d\n", code);
    uid = boundDriverUid; // preserve on error
  }
  http.end();
  return uid;
}

void pollDriverUid() {
  if (millis() - lastUidPoll < UID_POLL_MS) return;
  lastUidPoll = millis();

  String uid = fetchDriverUid();
  if (uid == boundDriverUid) return;

  if (uid.length() > 0) {
    boundDriverUid = uid;
    Serial.println("[BIND] Driver bound: " + uid);
    signalBlink(3);
    pushStatusToFirestore(driverStatus, true);
  } else {
    Serial.println("[BIND] Driver unbound");
    boundDriverUid = "";
    signalBlink(1);
    updateLEDs();
  }
}

// ──────────────────── Buzzer command (RTDB) ───────────────────────────────

void checkBuzzerCommand() {
  if (!wifiConnected) return;

  WiFiClientSecure client = freshClient();
  HTTPClient http;
  String url = rtdbUrl("/devices/" + deviceId + "/buzzer");
  http.setTimeout(5000);
  http.begin(client, url);
  int code = http.GET();

  if (code == 200) {
    String payload = http.getString();
    if (payload == "null" || payload == "") { http.end(); return; }

    StaticJsonDocument<200> doc;
    if (deserializeJson(doc, payload) == DeserializationError::Ok &&
        doc["action"] == "buzz") {
      unsigned long ms = doc.containsKey("duration")
                         ? doc["duration"].as<unsigned long>() : 5000;
      activateBuzzer(ms);
      http.end();

      // Delete node so it does not re-trigger
      WiFiClientSecure dc = freshClient();
      HTTPClient hd;
      hd.setTimeout(5000);
      hd.begin(dc, url);
      hd.sendRequest("DELETE");
      hd.end();
      return;
    }
  }
  http.end();
}

// ──────────────────── Button handlers (edge detection) ────────────────────

void handleButton1() {
  btn1State = digitalRead(BTN_PIN_1);
  // Detect falling edge: HIGH → LOW means button just pressed
  if (btn1Prev == HIGH && btn1State == LOW) {
    if (millis() - btn1Last > DEBOUNCE_MS) {
      btn1Last      = millis();
      driverStatus  = "FULL";
      pendingStatus = "FULL";
      statusDirty   = true;
      updateLEDs();   // instant LED feedback — no HTTP wait
      Serial.println("[BTN] FULL");
    }
  }
  btn1Prev = btn1State;
}

void handleButton2() {
  btn2State = digitalRead(BTN_PIN_2);
  if (btn2Prev == HIGH && btn2State == LOW) {
    if (millis() - btn2Last > DEBOUNCE_MS) {
      btn2Last      = millis();
      driverStatus  = "LIMITED";
      pendingStatus = "LIMITED";
      statusDirty   = true;
      updateLEDs();
      Serial.println("[BTN] LIMITED");
    }
  }
  btn2Prev = btn2State;
}

void handleButton3() {
  btn3State = digitalRead(BTN_PIN_3);
  if (btn3Prev == HIGH && btn3State == LOW) {
    if (millis() - btn3Last > DEBOUNCE_MS) {
      btn3Last      = millis();
      driverStatus  = "AVAILABLE";
      pendingStatus = "AVAILABLE";
      statusDirty   = true;
      updateLEDs();
      Serial.println("[BTN] AVAILABLE");
    }
  }
  btn3Prev = btn3State;
}

// ──────────────────── SoftAP / Web config ─────────────────────────────────

void handleRoot() {
  server.send(200, "text/html", R"(
<!DOCTYPE html><html><head>
<title>ESP32 Config</title>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>body{font-family:Arial;margin:40px;background:#f0f0f0}
.b{max-width:400px;margin:0 auto;background:#fff;padding:20px;border-radius:8px}
h1{text-align:center;color:#333}label{display:block;margin-top:15px;font-weight:bold}
input{width:100%;padding:8px;margin-top:5px;box-sizing:border-box;border:1px solid #ddd;border-radius:4px}
button{width:100%;padding:10px;margin-top:20px;background:#007bff;color:#fff;border:none;border-radius:4px;font-size:16px;cursor:pointer}</style>
</head><body><div class="b"><h1>ESP32 WiFi Setup</h1>
<form method="POST" action="/save">
<label>SSID<input type="text" name="ssid" required></label>
<label>Password<input type="password" name="pass" required></label>
<button>Save &amp; Connect</button></form></div></body></html>)");
}

void handleSave() {
  if (server.hasArg("ssid") && server.hasArg("pass")) {
    prefs.begin("wifi-config", false);
    prefs.putString("ssid", server.arg("ssid"));
    prefs.putString("pass", server.arg("pass"));
    prefs.end();
    server.send(200, "text/html", "<h1>Saved! Restarting…</h1>");
    delay(1000);
    ESP.restart();
  } else {
    server.send(400, "text/plain", "Missing fields");
  }
}

void startSoftAP() {
  WiFi.mode(WIFI_AP);
  WiFi.softAP(SOFTAP_SSID, SOFTAP_PASSWORD);
  Serial.printf("[AP] SSID:%s  IP:%s\n",
                SOFTAP_SSID, WiFi.softAPIP().toString().c_str());
  server.on("/",     handleRoot);
  server.on("/save", HTTP_POST, handleSave);
  server.begin();
}

void loadWiFiCredentials() {
  prefs.begin("wifi-config", true);
  savedSsid = prefs.getString("ssid", "");
  savedPass = prefs.getString("pass", "");
  prefs.end();
}

void connectWiFi() {
  if (savedSsid.length() == 0) { startSoftAP(); return; }
  Serial.print("[WIFI] Connecting");
  WiFi.mode(WIFI_STA);
  WiFi.begin(savedSsid.c_str(), savedPass.c_str());
  unsigned long t = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - t < 20000) {
    delay(300); Serial.print(".");
  }
  Serial.println();
  if (WiFi.status() == WL_CONNECTED) {
    wifiConnected = true;
    Serial.println("[WIFI] OK: " + WiFi.localIP().toString());
  } else {
    Serial.println("[WIFI] FAIL → SoftAP");
    startSoftAP();
  }
}

// ──────────────────── Setup & Loop ────────────────────────────────────────

void setup() {
  Serial.begin(115200);
  delay(100);
  Serial.println("\n=== ESP32 JeepJeep ===");

  pinMode(LED_PIN_1, OUTPUT); pinMode(LED_PIN_2, OUTPUT);
  pinMode(LED_PIN_3, OUTPUT); pinMode(BUZZER_PIN, OUTPUT);
  pinMode(BTN_PIN_1, INPUT_PULLUP);
  pinMode(BTN_PIN_2, INPUT_PULLUP);
  pinMode(BTN_PIN_3, INPUT_PULLUP);
  digitalWrite(LED_PIN_1, LOW); digitalWrite(LED_PIN_2, LOW);
  digitalWrite(LED_PIN_3, LOW); digitalWrite(BUZZER_PIN, LOW);

  loadWiFiCredentials();
  connectWiFi();

  if (wifiConnected) {
    delay(500);
    WiFiClientSecure c = freshClient();
    HTTPClient h;
    h.setTimeout(5000);
    h.begin(c, rtdbUrl("/devices/" + deviceId + "/deviceId"));
    h.addHeader("Content-Type", "application/json");
    h.PUT("\"" + deviceId + "\"");
    h.end();
    Serial.println("[INIT] Device registered. Waiting for driver login…");
  }

  // Seed button previous states so we don't get a phantom press on boot
  btn1Prev = digitalRead(BTN_PIN_1);
  btn2Prev = digitalRead(BTN_PIN_2);
  btn3Prev = digitalRead(BTN_PIN_3);

  Serial.println("[SYSTEM] Ready.");
}

void loop() {
  if (WiFi.getMode() == WIFI_AP) { server.handleClient(); return; }

  // WiFi watchdog
  if (WiFi.status() != WL_CONNECTED) {
    wifiConnected = false;
    Serial.println("[WIFI] Lost — reconnecting…");
    WiFi.reconnect();
    unsigned long t = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - t < 10000) delay(300);
    if (WiFi.status() == WL_CONNECTED) {
      wifiConnected = true;
      Serial.println("[WIFI] Reconnected");
      if (boundDriverUid.length() > 0)
        pushStatusToFirestore(driverStatus, true);
    }
  }

  // ── Time-critical: always run first, no HTTP in here ──
  tickBuzzer();
  handleButton1();
  handleButton2();
  handleButton3();
  // LEDs are already updated inside each handleButton, but call again
  // in case status changed from another source (bind/unbind)
  updateLEDs();

  // ── Deferred HTTP: only fires after button press settles ──
  if (statusDirty && millis() - lastStatusPush > STATUS_DEDUP_MS) {
    statusDirty = false;
    pushStatusToFirestore(pendingStatus, true);
  }

  // ── Periodic network tasks ──
  pollDriverUid();

  if (millis() - lastBuzzerCheck > BUZZER_CHECK_MS) {
    lastBuzzerCheck = millis();
    checkBuzzerCommand();
  }

  if (boundDriverUid.length() > 0 && millis() - lastHeartbeat > HEARTBEAT_MS) {
    lastHeartbeat = millis();
    Serial.println("[HB] " + driverStatus);
    pushStatusToFirestore(driverStatus, true);
  }

  // No delay() here — keep loop tight so buttons are always responsive
}
