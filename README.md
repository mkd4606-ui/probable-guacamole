# Control API — Universal Device Agent backend

> **Protocol contract:** `../PROTOCOL_V1.md` (root of this zip) — command/
> event/error envelope ka **frozen, canonical spec**. `lib/models/errors.dart`
> aur `routes/commands.dart` (protocol_version check) isi ko implement
> karte hain.

Yeh woh server hai jo pehle **poori tarah missing tha** — `shared_app`
sirf client code tha (commands bhejna), yeh us client ka doosra pehlu hai:
commands ko sahi device tak route karna, scoped keys manage karna, aur
dashboard/AI clients ko real-time events dena.

## Architecture — ek diagram mein

```
Dashboard/AI client                Control API (yeh server)              Device (shared_app)
       |                                    |                                    |
       |--- POST /devices/pair ------------>|                                    |
       |<-- {device_id, bearer_token} ------|                                    |
       |                                    |<--- WS /devices/{id}/agent --------|  (persistent,
       |                                    |         (device khud connect karta hai)  AgentConnection)
       |--- POST /api-keys (device auth) -->|                                    |
       |<-- {key_id, secret} ---------------|                                    |
       |                                    |                                    |
       |--- POST /commands (api-key auth) ->|                                    |
       |                                    |--- {"kind":"command",...} -------->|
       |                                    |                                    |--- executes via
       |                                    |                                    |    CommandDispatcher
       |                                    |<-- {"kind":"command_result",...} --|
       |<-- 200 OK {result} ----------------|                                    |
       |                                    |                                    |
       |--- WS /sessions/{id} ------------->|<-- {"kind":"event",...} -----------|
       |<-- task_progress/switch_event -----|                                    |
```

## Files

```
control_api/
  pubspec.yaml
  Dockerfile                     # Railway build isko khud detect karta hai
  railway.json                    # healthcheck + build config
  .dockerignore
  bin/server.dart              # entry point, wires everything
  lib/
    models/
      device.dart               # paired device + bearer token
      api_key.dart               # ApiKeyScope (9 toggles, matches Dart client) + ApiKeyRecord
      capabilities.dart           # static manifests for all 9 built capabilities
      activity.dart                # ActivityEvent (matches Dart client)
    storage/
      app_state.dart               # in-memory state — devices, keys, sessions, live connections
      persistence.dart              # JSON-file save/load — restart-survival (needs Railway Volume)
    auth/
      device_auth.dart              # Bearer token -> Device or ApiKey
    routes/
      devices.dart                  # pair, status, location, activity
      api_keys.dart                  # create/list/update/revoke
      capabilities.dart               # discovery + connector auth stub
      commands.dart                    # POST /commands (policy engine + routing) + switch API
    websocket/
      handlers.dart                    # /sessions/{id}, /screen/{id}, /devices/{id}/agent
```

## Endpoints — sab `api_client.dart` (Dart client) se exactly match karte hain

| Method | Path | Auth | Kaam |
|---|---|---|---|
| POST | `/devices/pair` | none | Device register karta hai, bearer token deta hai |
| GET | `/capabilities` | none | Sab registered capabilities |
| GET | `/capabilities/{name}/schema` | none | Ek capability ka schema |
| POST | `/capabilities/register` | none | Custom capability add |
| POST | `/connectors/{name}/auth` | none | **Stub** — real OAuth nahi |
| POST | `/api-keys` | device bearer | Nayi scoped key banao |
| GET | `/api-keys` | device bearer | Apni saari keys |
| PATCH | `/api-keys/{id}/permissions` | device bearer | Scope badlo |
| PATCH | `/api-keys/{id}/status` | device bearer | **Naya** — disable/re-enable (delete kiye bina) |
| DELETE | `/api-keys/{id}` | device bearer | Revoke |
| POST | `/commands` | api-key | **Core** — policy check + device tak route |
| POST | `/sessions/{id}/switch` | api-key | Universal Switch API |
| GET | `/devices/{id}/status` | none | Power/lock/location/network |
| POST | `/devices/{id}/location` | device bearer | Location report |
| GET | `/devices/{id}/activity` | none | Activity history |
| WS | `/sessions/{id}` | — | task_progress/switch_event stream |
| WS | `/screen/{id}` | — | Live screen frames |
| WS | `/devices/{id}/agent` | — | **Naya** — device ka persistent connection |

## Run karne ke liye

```bash
cd control_api
dart pub get
dart run bin/server.dart
# Control API listening on http://0.0.0.0:8080
```

Environment variable `PORT` se port badal sakte ho.

## Audit Progress Tracker

`Universal_Device_Agent_Developer_Fix_Audit.pdf` (developer ne provide
kiya) ka P0/P1 checklist yahan track ho raha hai — ek-ek item confirm
karke implement kiya ja raha hai:

| Item | Status |
|---|---|
| **Protocol freeze** (Order #1) | ✅ Done — `PROTOCOL_V1.md`, canonical error envelope (`lib/models/errors.dart`), `protocol_version` field command envelope mein, server validation |
| **Auth + scoped policy middleware** (Order #2) | ✅ Done — action-level `allowsAction()` (fail-closed), 3 naye scope toggles (`location`, `background`, `messagingReply` — akhri wala isliye alag kiya kyunki audit ka SCOPE-02 test specifically "read vs reply" ko alag scope maangta hai), `/sessions/{id}/switch` par bhi policy check, disable/re-enable endpoint. **Partial caveat:** `control.*` actions (pause/resume/stop) abhi bhi "koi bhi ek scope granted ho" wala interim policy use karte hain — poora fix Order #3 (TaskRecord) ke baad hi possible hai, jab session ko pata ho woh kis capability se shuru hui thi. |
| Task lifecycle / TaskRecord state machine (P0-01) | ⬜ Next |
| Capability registry persistence + schema validation (P1-01) | ⬜ |
| API-key flows (create/list/update/revoke) | ✅ already tha (is round se pehle) |
| Data transfer hardening (P1-08) | ⬜ |
| Live monitoring end-to-end verify (P1-03) | ⬜ (capability bani hai, audit-level verify baaki) |
| Background/notification/messaging adapters (P1-06) | 🟡 Android notifications + messaging adapters code mein (unverified, real device chahiye) |
| Location/network adapters (P1-07) | ✅ capability bani hai, permission-gating verify baaki |
| Connector OAuth (P0-07) | ⬜ (abhi stub hai) |
| Persistent activity/audit history (P1-09) | ✅ already tha (JSON persistence) |
| HTTPS/WSS, rate limits, secrets (P0-03/05/06) | ⬜ (P0-06 secret-hashing already tha) |
| Automated tests | ⬜ |
| Platform test matrix | ⬜ (sirf tumhare apne machine par possible) |

## Acceptance tests — is round ke baad kya cover hota hai

Audit ke "Acceptance Tests" table se, is round ke changes se yeh
tests **logically pass honi chahiye** (implementation unke expected
behavior ke mutabiq hai — lekin **run karke verify nahi kiya**, Dart SDK
na hone ki wajah se, jaisa upar bhi likha hai):

| ID | Test | Is round mein kya cover hua |
|---|---|---|
| AUTH-01 | Invalid API key → 401 | ✅ `deviceAuthMiddleware` + canonical `UNAUTHORIZED` error |
| AUTH-02 | Revoked key → immediate rejection | ✅ DELETE turant map se hata deta hai; auth middleware live-check karta hai |
| SCOPE-01 | Screen-only key requests `input.tap` → 403 | ✅ `allowsAction('input.tap')` sirf `touchInput` check karta hai |
| SCOPE-02 | `messaging.read` allowed, `messaging.reply` nahi | ✅ ab do alag toggles hain (`background` vs `messagingReply`) |

## Honest limitations — yeh production-ready nahi hai

1. **Persistence — ab hai, lekin Volume attach karna zaroori hai.**
   `lib/storage/persistence.dart` sab data (devices, API keys, activity
   log) ek JSON file mein save karta hai (`$DATA_DIR/state.json`, default
   `/data`), har mutation ke baad. **Lekin** Railway (ya koi bhi Docker
   host) mein by-default container ka filesystem bhi ephemeral hota hai
   — is JSON file ko restarts ke beech zinda rakhne ke liye Railway
   dashboard mein ek **Volume** `/data` par mount karna zaroori hai
   (`HOW_TO_CONNECT.md` mein step-by-step hai). SQLite/Postgres ki
   jagah jaan-bujh kar simple JSON file use ki — is scale (ek user ke
   devices) ke liye kaafi hai aur koi native dependency nahi chahiye
   (Docker build simple rehta hai).

2. **Pairing code validation nahi hai** — `POST /devices/pair` abhi
   `pairing_code` ko validate nahi karta (trust-on-first-use). Production
   mein pairing code ek short-lived server-side store mein match hona
   chahiye (jo native `PairingManager` generate karta hai, usay server ko
   bhi pata hona chahiye — abhi woh do islands hain, connect nahi).

3. **Connector OAuth** — `POST /connectors/{name}/auth` sirf ek stub hai.
   Real Google Drive/Slack/waghera OAuth flow connector-specific hota hai,
   yahan implement nahi kiya gaya.

4. **`control.pause`/`resume`/`stop`** — sirf acknowledge karte hain.
   Ek asal multi-step "task" state machine (jo yeh track kare ke konsa
   step chal raha hai, usko beech mein rok sake) **AI/orchestration layer**
   ka kaam hai jo is project mein kahin nahi bana — Control API sirf
   commands relay karta hai, task-level logic nahi rakhta.

5. **Background messaging (Section 9)** — `notifications.read_event`,
   `messaging.*` actions device-side `CommandDispatcher` mein explicitly
   `UnimplementedError` throw karte hain. Yeh device-side
   `NotificationListenerService`-jaisi cheez maangta hai jo kabhi nahi
   bani.

6. **No HTTPS/WSS, no rate limiting, no input validation beyond basic
   null-checks** — sab security-hardening abhi missing hai, yeh sirf
   architecture/contract demonstrate karta hai.

7. **Compile-verify nahi ho saka** — jaisa shared_app ke saath bhi hua,
   is sandbox mein Dart SDK download nahi ho saka (network-restricted),
   isliye `dart pub get`/`dart analyze` yahan nahi chal saka. Code
   carefully likha hai (shelf/shelf_router ka standard, well-documented
   API use kiya), lekin real verification tumhare apne machine par hi
   hogi.

## Stage 9 additions
- `GET /readyz` — 503 agar `DATA_DIR` likhne layak nahi (Railway Volume `/data` mount nahi). `GET /healthz` hamesha 200.
- Background timers: 30 s (stale devices + open-socket revalidation), hourly (`sweepTasks`).
- `CONNECTOR_ENCRYPTION_KEY` bina connector `auth` refuse hota hai. Dekhein `CONNECTORS.md`.
