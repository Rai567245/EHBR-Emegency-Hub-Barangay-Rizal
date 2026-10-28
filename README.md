# Emergency Hub – Barangay Rizal

A clean, empty system: **no sample data anywhere**. Everything residents see in the
app is entered by the barangay in the admin console, and everything residents
submit in the app shows up in the admin console.

```
ehbr/
├── server/   Node.js API + hosts the admin console   (no dependencies, no database to install)
├── admin/    Admin console – plain HTML / CSS / JS   (served by the server)
└── app/      Resident mobile/web app – Flutter
```

How they connect

```
 Flutter app  ──HTTP/JSON──►  server (port 3000)  ◄──HTTP/JSON──  Admin console (browser)
                                    │
                              server/data.json   (created on first run)
```

---------------------------------------------------------------------------

## 1. Start the server (needs Node.js 18+)

```
cd server
node server.js          # or: npm start
```

The **first time** it runs it creates the admin account and prints the password **once**:

```
Admin login  →  username: admin   password: xxxxxxxxxxxx
```

Copy it. (Lost it? `node server.js --reset-admin` makes a new one.
You can also choose it yourself: `ADMIN_PASSWORD='your-password' node server.js`.)

Open **http://localhost:3000/admin/** and sign in.

## 2. Set up the barangay (in the admin console)

Nothing shows in the app until you add it:

| Where | What to add | Shows up in the app as |
|-------|-------------|------------------------|
| Settings → Barangay profile | name, city, hotline, default map position | header text, login screen, Contacts |
| Settings → SOS | number the SOS button dials (default 911) | Home SOS button |
| Settings → Emergency contacts | police / fire / medical / utility numbers | Contacts tab + Home quick tiles |
| Database → Zones / Puroks | list of zones | sign-up dropdown |
| Database → Evacuation Centers | name, capacity, status, coordinates | Home + Map tab |
| Announcements | alerts / advisories / events | News tab + Home |

Reports flow the other way: a resident files one → it appears in **Reports** (and on the
**Incident Map** if it has GPS) → you **Verify** → it becomes visible to all residents on
their Map tab → **Dispatch** → **Resolve**. The reporter sees each step under Profile → My Reports.

## 3. Run the Flutter app

Install Flutter (https://docs.flutter.dev/get-started/install), then:

```
cd app
flutter create . --org ph.barangay --project-name ehbr_app --platforms=web,android,ios
dart run tool/patch_platforms.dart        # adds Android/iOS permissions (one time)
flutter pub get
flutter run -d chrome                     # or pick a device: flutter devices
```

Where is the server? The app finds it automatically in these cases:

| Running on | Server address used |
|------------|--------------------|
| Chrome, desktop, iOS simulator | `http://localhost:3000` |
| Android emulator | `http://10.0.2.2:3000` |
| **A real phone** | your computer's LAN IP – pass it in: |

```
flutter run --dart-define=API_BASE=http://192.168.1.20:3000
```

(Phone and computer must be on the same Wi-Fi. Use your computer's real IP; allow Node through
the firewall if asked.) If the app can't reach the server it says so and shows the address it tried.

The Map tab and the admin Incident Map use OpenStreetMap tiles – they need internet access.

## 4. Try it end to end

1. Admin console → add a zone, an evacuation center (with coordinates) and an announcement.
2. App → **Sign up** → you land on Home and see exactly what you just added.
3. App → **Report Incident** → fill it in (tap *Use GPS* to attach your location) → submit.
4. Admin console → **Reports** → open it → **Verify report**.
5. App → **Map** tab → pull down to refresh → the verified report appears.
6. Admin → **Dispatch**, then **Mark resolved** → check **Profile → My Reports** in the app.
7. Tap the **bell** in the app: you'll see the announcement and the updates on your report (see step 5 for phone push).

## 4b. When there is no internet

The app is built so the important things still work with no signal:

* **SOS and every emergency number still work.** The settings (SOS number, barangay hotline and
  all emergency contacts you entered in the admin console) are saved on the phone each time the app
  connects, and used when it can't. Phone calls go through the normal mobile network, not the internet.
* **Reports are never lost.** If a report can't be sent, the app shows **"Report saved on your phone"**
  together with the full list of emergency numbers, and keeps the report in a queue on the phone.
  It sends automatically as soon as a connection returns **while the app is open** (it checks every
  15 seconds and whenever the app is reopened). The resident then sees "Back online – your saved
  report reached the barangay" and gets a notification.
* **No duplicates, honest times.** Each report carries a random ID, so a retry can never file the
  same report twice, and the admin console shows both when it was filed on the phone and when it arrived.
* **Home still opens** offline (SOS, report buttons, saved numbers); a banner explains that news and
  evacuation centers will refresh when the connection is back. The app also opens offline if the
  resident was already logged in.
* Waiting reports are listed under Home (yellow banner) and Profile → My Reports, where they can be
  sent now or deleted.

Limits to be aware of: a phone that is *completely* out of signal cannot send until it has one again,
and a report waiting in the queue will not send while the app is fully closed. The very first time
the app is ever opened it needs internet once (to download the settings).

---------------------------------------------------------------------------

## 5. Notifications

There are two layers. The first needs nothing from you; the second needs a free Firebase project.

**A. In-app notifications (work out of the box).** The bell in the app's top bar shows a red
badge with the number of unread notifications and opens the list. Residents get one when:

* the admin posts an **announcement** (everyone),
* a report is **verified** (everyone – a safety notice; switch off in Settings → "Notify nearby residents when a report is verified"),
* **their own report** is verified, dispatched, resolved or rejected (only that resident).

The badge refreshes every 45 seconds, when the app is reopened, and when a push arrives.
Residents who sign up later don't see old notifications.

**B. Push notifications (the phone buzzes even when the app is closed).** Uses Firebase Cloud
Messaging (free). One-time setup:

1. Go to https://console.firebase.google.com → **Add project** (any name; Analytics not needed).
2. Connect the app (needs Node.js, and the Flutter commands from step 3 already run with `--org ph.barangay`):
   ```
   npm install -g firebase-tools
   firebase login
   dart pub global activate flutterfire_cli
   cd app
   flutterfire configure      # pick your project, tick Android (and iOS if you have a Mac)
   ```
   This writes `google-services.json`, wires the Android build, and **replaces**
   `app/lib/firebase_options.dart` with your real settings.
3. Give the server permission to send: Firebase console → ⚙ Project settings → **Service accounts**
   → **Generate new private key** → save the file as `server/firebase-service-account.json`
   (keep it secret – never share or commit it) → restart the server. It should print
   `Push   on (Firebase)`. The admin **Announcements** page also shows "Push is on".
4. Run the app on a **real Android phone** (`flutter run`), log in, tap **Allow** when asked
   about notifications. Post an announcement in the admin console with the push switch on –
   the phone buzzes, even if the app is closed.

iPhone extras: an Apple Developer account (paid), upload an APNs key in Firebase → Project settings →
Cloud Messaging, and in Xcode enable **Push Notifications** and **Background Modes → Remote notifications**.
iOS simulators generally can't receive push – use a real iPhone.

Good to know

* Everyone with the app gets announcements and verified-incident alerts via a Firebase topic
  (`residents`); personal report updates go to that resident's own phone(s). Logging out
  (or an expired login) stops the phone receiving them.
* If the app is open, a banner appears inside the app instead of a system notification.
* Push does not work in the browser build – the bell list still does.
* Without step 2/3 nothing breaks: push stays off and the bell list keeps working.
* Not set up: SMS. It needs a paid SMS provider; ask if you want it added.

---------------------------------------------------------------------------

## 6. Rate limits (protection against floods and password guessing)

The server limits how fast anyone can call it. Residents never notice these limits in normal use; they only stop scripts and attackers. When a limit is hit the server answers **429** with a `Retry-After` header, and the app waits and tries again by itself (a report is kept on the phone and sent later, never lost).

| What | Default limit |
| --- | --- |
| Any request from one IP (not logged in) | 120 per minute |
| Any request from one logged-in account | 240 per minute |
| Login attempts from one IP | 40 per 10 minutes |
| Wrong passwords for one number **from one IP** | 10 per 15 minutes, then locked for that IP + number |
| Wrong passwords for one number from anywhere | 50 per 15 minutes |
| New accounts from one IP | 10 per hour |
| Reports per resident | 10 per 10 minutes |
| Extra reserve for **Critical** reports | 10 more per 10 minutes |
| Push-token registrations per resident | 30 per hour |
| Announcements / "show contact number" / add resident (admin) | 30 / 60 / 60 per hour |

Things worth knowing:

- **A resent report never counts.** The phone's retry of a report that already arrived is recognised first and answered as success, so a bad connection can't use up the allowance.
- **Critical reports have their own reserve**, so someone spamming small reports can't block a real emergency.
- **Many residents share one IP on mobile data**, so the per-IP limits are generous. Wrong-password lockouts are per IP *and* number, so a stranger cannot lock a resident out from their own phone.
- **Behind a reverse proxy** (Caddy, Nginx, Cloudflare Tunnel), set `TRUST_PROXY=1` (the number of proxies in front of the server). Without it the server only trusts the real connection address and ignores `X-Forwarded-For`, so it can't be spoofed, but every resident would then look like the proxy's IP. The server prints a warning once if it sees the header without `TRUST_PROXY`.
- Password hashing runs in the background, at most 4 at a time, so a burst of logins cannot freeze the server. Requests bigger than 100 KB are refused, and slow connections are cut after 15 seconds.
- **Change a limit** with `RATE_LIMITS`, for example `RATE_LIMITS='{"report":[20,600],"anonIp":[300,60]}'` (`[max, seconds]`). **Never limit your own office** with `RATE_LIMIT_ALLOW=203.0.113.5,203.0.113.6`.
- Counts live in memory and reset when the server restarts. They are per server, which is fine for one barangay.
- Run the checks with `cd server && npm test`.

## 7. Forgot password

Two ways, and the app picks automatically:

**A. Email code (free, automatic).** Residents can add an email when they sign up, or later under *Profile → Account details → Add email* (this asks for their password). On *Forgot password?* the server emails a 6-digit code that works once and expires in 15 minutes; the resident types it into the app with a new password. Nobody at the office has to be involved.

**B. Barangay office (for residents with no email, or whose email didn't arrive).** The resident taps *Ask the barangay office*. A request appears in the admin console (**Database → Residents → Password reset requests**). You can also press the lock button on any resident's row for someone who walks in. **Confirm who they are first** (valid ID, or call back the number on file), then press **Issue code** and read out the 8-digit code (works once, 30 minutes).

### Turning on email (free options, about 5 minutes)

The server needs an email account it can send from. The simplest free choice is a Gmail account made for the barangay:

1. In that Gmail account turn on 2-step verification, then create an **App password** (Google Account → Security → App passwords).
2. Start the server with these settings:

```
SMTP_HOST=smtp.gmail.com
SMTP_PORT=465
SMTP_USER=yourbarangay@gmail.com
SMTP_PASS=<the 16-letter app password>
SMTP_FROM="Barangay Rizal <yourbarangay@gmail.com>"
```

Gmail allows roughly 500 emails a day, far more than a barangay needs. Brevo (free, 300 a day; host `smtp-relay.brevo.com`, port 465) and other providers work the same way. Keep these values secret (like the admin password), never put them in the app or in Git. When they are missing the server prints "Email codes: off" and every reset goes through the office (option B).

### Safety built in
Codes are stored only as a hash; 5 wrong tries lock a code; the app gives the same reply for any number, so nobody can use it to find out who is registered; requests are limited to 3 per hour per number; after a reset every old session is signed out and the resident gets an in-app "Your password was changed" notice; the old password keeps working until a code is used. Requests, emails sent and resets appear in the activity log.

Things to know: the emailed code goes to whatever email the resident entered, which is not verified at sign-up. A typo means the code goes nowhere (they can use option B), and the code is useless without the resident's number. Someone could also make the server email a resident a code by entering their number; that is limited to 3 per hour per number and changes nothing. Staff should **never give a code to someone they have not identified**, and residents should never share an emailed code with anyone.

## 8. Keeping the maps inside the barangay (service area)

In the admin console go to **Settings → Barangay** and set:
- **Default map latitude / longitude**: the middle of your barangay. (Right-click the spot in Google Maps and copy the two numbers.)
- **Service area radius (km)**: for example `3`. The default `0` means no limit.

What it does once set:
- The resident app's **Map** and the admin **Incident Map / Dashboard map** can't be dragged or zoomed out past that area.
- A report whose GPS is **outside** the area is **never refused** (a real emergency just outside the line still matters), but it is flagged **"Outside the barangay area"** in the admin report panel, and the resident is told their GPS looks outside the area.
- Reports with only a typed address (no GPS) are not affected.

**Exact border (recommended).** Instead of a radius you can paste the real border:
1. Go to **geojson.io** (free, no account). Zoom to your barangay.
2. Pick the **polygon tool** (the pentagon icon on the right) and click once on each corner of the border, following the streets. Double-click to finish.
3. Copy **all** the text from the panel on the left ("JSON" tab).
4. In **Settings → Barangay → Barangay border**, paste it and click **Save changes**.

With a border set, both maps are limited to that shape (with a little room around it), it is drawn as a red outline, and a report is flagged "Outside the barangay area" only if its GPS is outside the outline. The radius is ignored. Clear the box to go back to the radius.

Note: until you change the default centre, it points to a placeholder in Manila. Set your own latitude and longitude first.

## 9. Road blockages

Roads that are closed for a while (flood, accident, road works, fallen tree, a parade) can be marked by the admin and cleared when they reopen.

**Mark one:** admin console → **Road Blockages** → click the map where the road is blocked (drag the pin to adjust) → type the road name, pick a reason, add details if you like → **Mark road as blocked**. Optionally set an *Expected to reopen* time, and tick **Notify all residents** to send them an alert (it appears in the app's bell and as a push notification when push is on).

**Clear one:** in the **Active blockages** list press **Road is open again**. It disappears from every resident's map right away. You can also **Edit** the name, reason, details or expected reopening time.

What residents see: the app's **Map** tab shows a dark ⛔ marker for each blocked road, with a **Blocked** filter chip and a list entry. If you set an expected reopening time, the blockage hides itself from residents after that time. In the admin it stays in the list marked **TIME PASSED** until you remove it, so nothing is forgotten.

Staff also see blocked roads (dark markers) on the admin **Incident Map**. Every add, edit and removal is written to the activity log.

## Notes before going live

* **Use HTTPS.** Passwords and tokens travel over the network. Put the server behind a reverse
  proxy with a certificate (Caddy and nginx both make this easy), then set
  `CORS_ORIGIN=https://your-domain` and build the app with
  `--dart-define=API_BASE=https://your-domain`. On Android you can then remove
  `usesCleartextTraffic` from the manifest.
* **Back up `server/data.json`** – it *is* the database (residents, reports, settings).
* Passwords are stored hashed (scrypt); sessions last 30 days; login is rate-limited.
* Residents never see other residents' names or contact numbers. In the admin console contact
  numbers are masked and revealing one is written to the activity log (Data Privacy Act).
* This single-file JSON store is fine for a barangay-sized pilot. For thousands of daily users,
  move storage to PostgreSQL or similar – the API surface in `server/server.js` stays the same.
* Not built yet: photo/video upload on reports, SMS (the "SMS fallback" and "auto-escalate" switches in
  Settings are saved but don't do anything yet), password reset by SMS, multiple admin accounts,
  and the "SOS confirmation" screen from the Figma file (the "Report submitted" and "Report saved
  offline" screens are built).
* The emblem is a placeholder icon – drop your barangay logo into `EhbrEmblem`
  (`app/lib/widgets/auth_widgets.dart`).

## 10. Photos on reports (up to 3)

- The app shrinks each photo (max 1280 px, JPEG quality 70) and sends it with the report. Photos wait in the offline queue with the report.
- The server keeps only real JPEG/PNG files under 1.5 MB, max 3 per report, in `server/uploads/` (set `UPLOAD_DIR` to move it). **Back this folder up with `data.json`.**
- Only the resident who filed the report and admins can open a photo (`GET /api/photos/:name`). Public reports never include photos.
- iOS: add `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` to `ios/Runner/Info.plist`. Android needs nothing extra.

## 11. PostgreSQL database

The server uses **PostgreSQL when `DATABASE_URL` is set**, and falls back to `server/data.json` when it is not.

**Set up (Windows / PowerShell)**
1. In pgAdmin: right-click *Databases* → *Create* → *Database…* → name it `ehbr` → Save.
2. In the `server` folder run `npm install` (once – it adds the `pg` package).
3. Start the server with the connection set:
   ```powershell
   $env:DATABASE_URL = "postgres://postgres:YOUR_PASSWORD@localhost:5432/ehbr"
   node server.js
   ```
   If the password has symbols such as `@ # / :`, write them URL-encoded (`@` → `%40`, `#` → `%23`).
4. First start with an empty database: the server creates the tables and **copies your existing `data.json` in** (accounts, reports, settings). Keep `data.json` as a backup afterwards.
5. In pgAdmin refresh the `ehbr` database → *Schemas → public → Tables*: `users`, `reports`, `announcements`, `centers`, `blockages`, `notifications`, `resets`, `activity`, `sessions`, `meta`. Each row is `id` + a `doc` JSON column. Example query: `select id, doc->>'type', doc->>'status' from reports order by updated_at desc;`

**Hosted databases (Supabase, Neon, …):** use their connection string as `DATABASE_URL` and also set `DATABASE_SSL=require`.

**Notes**
- Changes are written to PostgreSQL within a fraction of a second and the server flushes on Ctrl+C / stop. Don't edit rows in pgAdmin while the server is running – the server keeps its own copy and would overwrite your edit.
- Run **one** server process per database.
- Back up with `pg_dump -U postgres ehbr > ehbr-backup.sql` (and the `uploads` folder for photos).

## 12. Admin console: newer screens

- **Reports**: filters, export (masked), reject/resolve/dispatch/escalate/request-info dialogs, on-site step, call-reporter dialog.
- **Dashboard**: quick actions (announcement, add responder, daily report), bell panel, search.
- **Database**: residents with zone/vulnerability filters, details drawer, add/edit, privacy export (reason required, always masked), Responders tab, teams, zone captain and flood risk.
- **Settings** (tabs): General (validated, Save disabled until errors are fixed), Alerts & Escalation (auto-escalate minutes, escalation chain, announcement templates), Data & Privacy (access log + export), Emergency Contacts, Zones, Account & Security. Leaving with unsaved changes asks first.
- Not built, because the server has a single admin account: Users & Roles and Invite user, Duty status. Auto-escalation, SMS and quiet hours are not sent yet.
