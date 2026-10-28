'use strict';
/**
 * Emergency Hub – Barangay Rizal API + admin file server.
 * Zero dependencies (Node 18+). Data lives in a JSON file.
 *
 *   node server.js                 start on :3000
 *   node server.js --reset-admin   create/reset the admin password and print it
 *
 * Env: PORT, DATABASE_URL (PostgreSQL), DATA_FILE (used when DATABASE_URL is empty), ADMIN_PASSWORD (first run), CORS_ORIGIN (default *)
 */
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const push = require('./push');
const mailer = require('./mailer');
const { createLimiter, clientIp, createGate, parseOverrides } = require('./ratelimit');

const PORT = Number(process.env.PORT) || 3000;
const DATA_FILE = process.env.DATA_FILE || path.join(__dirname, 'data.json');
const ADMIN_DIR = path.join(__dirname, '..', 'admin');
const CORS_ORIGIN = process.env.CORS_ORIGIN || '*';
const UPLOAD_DIR = process.env.UPLOAD_DIR || path.join(__dirname, 'uploads');
const MAX_PHOTOS = 3, MAX_PHOTO_BYTES = 1.5 * 1024 * 1024;
const SESSION_MS = 30 * 24 * 3600 * 1000;

const REPORT_TYPES = {
  incident: ['Fire', 'Medical emergency', 'Road accident', 'Flooding', 'Crime / safety threat'],
  hazard: ['Fallen tree', 'Fallen electrical wire', 'Blocked drainage', 'Open manhole', 'Damaged structure', 'Other hazard'],
};
const ALL_TYPES = [...REPORT_TYPES.incident, ...REPORT_TYPES.hazard];
const URGENCIES = ['Low', 'Medium', 'High', 'Critical'];
const URGENCY_RANK = { Low: 1, Medium: 2, High: 3, Critical: 4 };
const STATUSES = ['NEW', 'VERIFIED', 'DISPATCHED', 'RESOLVED', 'REJECTED'];
const kindOf = (type) => (REPORT_TYPES.incident.includes(type) ? 'incident' : 'hazard');

// ------------------------------------------------------------------ storage
const emptyDb = () => ({
  settings: {
    barangay: { name: '', city: '', region: '', hotline: '' },
    mapCenter: { lat: 14.5995, lng: 120.9842, radiusKm: 0, boundary: [] },   // boundary = [[lat,lng],...] border of the barangay (empty = use radius); radiusKm = service area around the centre; 0 = no limit (set it in Settings)
    sos: { number: '911', holdToConfirm: true },
    rules: { notifyOnVerify: true, autoEscalate: true, escalateMinutes: 5, smsFallback: false, allowAnonymous: true },
    zones: [],
    contacts: [],
    responders: [],            // people on the response teams: [{id,name,contact,team,role,availability}]
    zoneInfo: {},              // per zone/purok: { "Purok 1": { captain, floodRisk } }
    teams: [],                 // responder teams the admin can assign: [{id,name,note}]
    escalation: { targets: [] }, // higher-level offices a report can be escalated to: [{id,name,note}]
  },
  users: [], reports: [], announcements: [], centers: [], activity: [], sessions: {}, notifications: [], resets: [], blockages: [],
  counters: { report: 0 },
});

let db = emptyDb();
function load() {
  try {
    const raw = JSON.parse(fs.readFileSync(DATA_FILE, 'utf8'));
    const base = emptyDb();
    db = { ...base, ...raw, settings: { ...base.settings, ...(raw.settings || {}) } };
    for (const k of ['barangay', 'mapCenter', 'sos', 'rules']) db.settings[k] = { ...base.settings[k], ...(db.settings[k] || {}) };
  } catch (e) {
    if (e.code !== 'ENOENT') { console.error('Could not read', DATA_FILE, e.message); process.exit(1); }
  }
}
// DATABASE_URL set  -> PostgreSQL (see store.js). Not set -> the single data.json file (handy for quick tests).
const DATABASE_URL = process.env.DATABASE_URL || '';
const pg = DATABASE_URL ? require('./store').createStore(DATABASE_URL) : null;
function save() {
  if (pg) return pg.save();
  const tmp = DATA_FILE + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(db, null, 2));
  fs.renameSync(tmp, DATA_FILE);
}
function normalize(raw) {
  const base = emptyDb();
  const d = { ...base, ...raw, settings: { ...base.settings, ...(raw.settings || {}) } };
  for (const k of ['barangay', 'mapCenter', 'sos', 'rules']) d.settings[k] = { ...base.settings[k], ...(d.settings[k] || {}) };
  return d;
}
/** Loads from PostgreSQL. On the very first start with an empty database, copies an existing data.json in. */
async function loadFromPg() {
  await pg.init();
  pg.bind(() => db);
  if (!(await pg.hasData())) {
    let raw = null;
    try { raw = JSON.parse(fs.readFileSync(DATA_FILE, 'utf8')); } catch (e) { if (e.code !== 'ENOENT') throw e; }
    if (raw) {
      db = normalize(raw);
      await pg.flush();
      console.log(`[db] Empty database – imported ${db.users.length} users and ${db.reports.length} reports from ${DATA_FILE}. You can keep that file as a backup.`);
      return;
    }
    db = emptyDb();
    await pg.flush(); // creates the settings rows so we know this database has been initialised
    return;
  }
  db = normalize(await pg.loadInto(emptyDb()));
}

// ------------------------------------------------------------------ helpers
const nowIso = () => new Date().toISOString();
const newId = () => crypto.randomUUID();
const str = (v, max = 200) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
const normContact = (v) => str(v, 40).replace(/[\s\-()]/g, '');
const isPhone = (v) => /^\+?\d{7,15}$/.test(v);
const num = (v) => (v === '' || v === null || v === undefined ? NaN : Number(v));

// scrypt runs on the thread pool (not the main loop) and at most 4 hashes run at once,
// so a burst of logins can't freeze the server for everyone else (e.g. someone filing an SOS).
const scryptAsync = (pw, salt) => new Promise((ok, no) => crypto.scrypt(pw, salt, 64, (e, k) => (e ? no(e) : ok(k))));
const hashGate = createGate(4, 50);
const hashPwSync = (pw) => { const salt = crypto.randomBytes(16); return salt.toString('hex') + ':' + crypto.scryptSync(pw, salt, 64).toString('hex'); };
function hashPw(pw) {
  const salt = crypto.randomBytes(16);
  return hashGate(async () => salt.toString('hex') + ':' + (await scryptAsync(pw, salt)).toString('hex'));
}
function checkPw(pw, stored) {
  const [s, h] = String(stored).split(':');
  if (!s || !h) return Promise.resolve(false);
  return hashGate(async () => {
    const a = await scryptAsync(pw, Buffer.from(s, 'hex'));
    const b = Buffer.from(h, 'hex');
    return a.length === b.length && crypto.timingSafeEqual(a, b);
  });
}
function log(text, kind = 'info') {
  db.activity.unshift({ at: nowIso(), text, kind });
  if (db.activity.length > 200) db.activity.length = 200;
}
// ------------------------------------------------------------------ notifications
// userId === null means "every resident" (also sent to the FCM topic `residents`).
function dropToken(token) {
  for (const u of db.users) if (u.deviceTokens) u.deviceTokens = u.deviceTokens.filter((t) => t.token !== token);
  save();
}
function notify({ userId = null, kind, title, body, refId = '', category = '', sendPush = true }) {
  const n = { id: newId(), userId, kind, category, title: str(title, 100), body: str(body, 300), refId, createdAt: nowIso() };
  db.notifications.push(n);
  const cutoff = Date.now() - 90 * 864e5;
  db.notifications = db.notifications.filter((x) => new Date(x.createdAt).getTime() > cutoff).slice(-1000);
  if (sendPush && push.enabled()) {
    const msg = { title: n.title, body: n.body, data: { kind, refId, category } };
    const fail = (e) => console.error('[push]', e.message);
    if (userId) {
      const u = db.users.find((x) => x.id === userId);
      for (const t of (u && u.deviceTokens) || []) push.send({ token: t.token }, msg).then((r) => { if (r.dead) dropToken(t.token); }).catch(fail);
    } else {
      push.send({ topic: 'residents' }, msg).catch(fail);
    }
  }
  return n;
}
const visibleTo = (user) => db.notifications.filter((n) => (n.userId === null || n.userId === user.id) && n.createdAt >= user.createdAt);

const pubUser = (u) => ({
  id: u.id, role: u.role, firstName: u.firstName, lastName: u.lastName,
  contact: u.contact, email: u.email || '', address: u.address, zone: u.zone, createdAt: u.createdAt,
});
// Distance in km between two GPS points (haversine).
function kmBetween(a, b, c, d) {
  const R = 6371, rad = (x) => (x * Math.PI) / 180;
  const h = Math.sin(rad(c - a) / 2) ** 2 + Math.cos(rad(a)) * Math.cos(rad(c)) * Math.sin(rad(d - b) / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}
// True when a report's GPS is outside the barangay's service area (reports are still accepted – it is only flagged).
function pointInPolygon(lat, lng, ring) {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [yi, xi] = ring[i], [yj, xj] = ring[j];
    if ((yi > lat) !== (yj > lat) && lng < ((xj - xi) * (lat - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}
function outsideArea(lat, lng) {
  const m = db.settings.mapCenter;
  if (lat === null || !m) return false;
  if (m.boundary && m.boundary.length >= 3) return !pointInPolygon(lat, lng, m.boundary);   // exact border wins
  if (!m.radiusKm) return false;
  return kmBetween(m.lat, m.lng, lat, lng) > m.radiusKm;
}
// Accepts what geojson.io / OpenStreetMap exports (a Polygon, Feature or FeatureCollection) and keeps one outline as [[lat,lng],...].
function cleanBoundary(v) {
  if (v === undefined || v === null || v === '') return [];
  let g = v;
  if (typeof g === 'string') { try { g = JSON.parse(g); } catch { throw bad('The border is not valid GeoJSON. Paste the whole text from geojson.io.'); } }
  if (Array.isArray(g)) g = { type: 'Polygon', coordinates: [g.map(([a, b]) => [b, a])] };   // already [[lat,lng],...]
  if (g.type === 'FeatureCollection') g = (g.features || [])[0];
  if (g && g.type === 'Feature') g = g.geometry;
  if (!g || !['Polygon', 'MultiPolygon'].includes(g.type)) throw bad('The border must be a Polygon drawn on the map.');
  let ring = g.type === 'Polygon' ? g.coordinates[0] : g.coordinates[0][0];
  if (!Array.isArray(ring)) throw bad('The border has no points.');
  ring = ring.map((p) => [num(p[1]), num(p[0])]);                                             // GeoJSON is [lng,lat]
  if (ring.some(([a, b]) => Number.isNaN(a) || Number.isNaN(b) || a < -90 || a > 90 || b < -180 || b > 180)) throw bad('The border has an invalid coordinate.');
  const [f, l] = [ring[0], ring[ring.length - 1]];
  if (ring.length > 1 && f[0] === l[0] && f[1] === l[1]) ring.pop();                           // drop the repeated closing point
  if (ring.length < 3) throw bad('The border needs at least 3 points.');
  if (ring.length > 2000) throw bad('The border has too many points (max 2000). Simplify it in geojson.io.');
  return ring.map(([a, b]) => [Math.round(a * 1e6) / 1e6, Math.round(b * 1e6) / 1e6]);
}
const mask = (c) => (c && c.length >= 8 ? `${c.slice(0, 4)} • • • ${c.slice(-4)}` : '••••');
const fullName = (u) => (u ? `${u.firstName} ${u.lastName}`.trim() : 'Unknown');

function issueToken(userId) {
  const token = crypto.randomBytes(32).toString('hex');
  db.sessions[token] = { userId, at: Date.now() };
  save();
  return token;
}
function userFromReq(req) {
  const m = /^Bearer ([a-f0-9]{64})$/.exec(req.headers.authorization || '');
  if (!m) return null;
  const s = db.sessions[m[1]];
  if (!s) return null;
  if (Date.now() - s.at > SESSION_MS) { delete db.sessions[m[1]]; save(); return null; }
  return db.users.find((u) => u.id === s.userId) || null;
}

// ------------------------------------------------------------------ rate limits (see ratelimit.js)
const TRUST_PROXY = Math.max(0, parseInt(process.env.TRUST_PROXY || '0', 10) || 0);
const limiter = createLimiter({
  overrides: parseOverrides(process.env.RATE_LIMITS),
  allow: (process.env.RATE_LIMIT_ALLOW || '').split(',').map((x) => x.trim()).filter(Boolean),
});
let warnedXff = false;
const ipOf = (req) => {
  if (!TRUST_PROXY && req.headers['x-forwarded-for'] && !warnedXff) {
    warnedXff = true;
    console.warn('\n  Note: a request carried X-Forwarded-For but TRUST_PROXY is not set, so it is ignored.\n  If this server sits behind a reverse proxy, set TRUST_PROXY=1 or every resident will share one rate limit.\n');
  }
  return clientIp(req, TRUST_PROXY);
};
function limit(rule, key, cost = 1) {
  const r = limiter.hit(rule, key, cost);
  if (!r.ok) throw new HttpError(429, 'Too many requests. Please wait a moment and try again.', r.retryAfter);
}

class HttpError extends Error { constructor(status, msg, retryAfter) { super(msg); this.status = status; this.retryAfter = retryAfter; } }
const bad = (msg) => new HttpError(400, msg);

function send(res, status, body, headers = {}) {
  const data = typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'X-Content-Type-Options': 'nosniff',
    'Cache-Control': 'no-store',
    ...headers,
  });
  res.end(data);
}
function readBody(req, max = 100000) {
  return new Promise((resolve, reject) => {
    let size = 0; const chunks = [];
    req.on('data', (c) => { size += c.length; if (size > max) { reject(new HttpError(413, 'Body too large')); req.pause(); } else chunks.push(c); });
    req.on('end', () => {
      if (!chunks.length) return resolve({});
      try { resolve(JSON.parse(Buffer.concat(chunks).toString('utf8'))); } catch { reject(bad('Invalid JSON')); }
    });
    req.on('error', reject);
  });
}

// ------------------------------------------------------------------ validation
function cleanLatLng(lat, lng) {
  const a = num(lat), b = num(lng);
  if (Number.isNaN(a) || Number.isNaN(b)) return { lat: null, lng: null };
  if (a < -90 || a > 90 || b < -180 || b > 180) throw bad('Coordinates out of range');
  return { lat: a, lng: b };
}
// Optional email, used only to send password-reset codes.
function cleanEmail(v) {
  const e = str(v, 120).toLowerCase();
  if (!e) return '';
  if (!/^[^\s@<>,;"']+@[^\s@<>,;"']+\.[^\s@<>,;"']+$/.test(e)) throw bad('Enter a valid email address, or leave it empty');
  return e;
}
const VULN = ['Senior', 'PWD', 'Infant', 'Pregnant'];
// Optional, staff-entered welfare details (never taken from the resident's own sign-up).
function cleanWelfare(b) {
  const n = Math.floor(Number(b.householdSize));
  const v = Array.isArray(b.vulnerability) ? b.vulnerability : String(b.vulnerability || '').split(',');
  return { householdSize: Number.isFinite(n) ? Math.max(0, Math.min(50, n)) : 0, vulnerability: [...new Set(v.map((x) => String(x).trim()).filter((x) => VULN.includes(x)))] };
}
function newUser(b, role) {
  const firstName = str(b.firstName, 60), lastName = str(b.lastName, 60);
  const contact = normContact(b.contact);
  const address = str(b.address, 200), zone = str(b.zone, 40), email = cleanEmail(b.email);
  if (!firstName || !lastName) throw bad('First and last name are required');
  if (!isPhone(contact)) throw bad('Enter a valid contact number');
  if (!address) throw bad('Address is required');
  if (db.settings.zones.length && !db.settings.zones.includes(zone)) throw bad('Select a valid zone');
  if (db.users.some((u) => u.contact === contact)) throw new HttpError(409, 'That contact number is already registered');
  return { id: newId(), role, firstName, lastName, contact, email, address, zone, passwordHash: null, createdAt: nowIso(), notifReadAt: nowIso(), deviceTokens: [] };
}
function cleanSettings(b) {
  const s = {};
  if (b.barangay) s.barangay = { name: str(b.barangay.name, 80), city: str(b.barangay.city, 80), region: str(b.barangay.region, 40), hotline: str(b.barangay.hotline, 30) };
  if (b.mapCenter) {
    const { lat, lng } = cleanLatLng(b.mapCenter.lat, b.mapCenter.lng);
    if (lat === null) throw bad('Map center needs a valid latitude and longitude');
    const rk = num(b.mapCenter.radiusKm);
    if (!Number.isNaN(rk) && (rk < 0 || rk > 100)) throw bad('Service area radius must be between 0 and 100 km (0 = no limit)');
    s.mapCenter = { lat, lng, radiusKm: Number.isNaN(rk) ? 0 : rk, boundary: cleanBoundary(b.mapCenter.boundary) };
  }
  if (b.sos) {
    const number = str(b.sos.number, 20);
    if (!/^[\d+*#]{2,20}$/.test(number)) throw bad('SOS number may only contain digits, + * #');
    s.sos = { number, holdToConfirm: !!b.sos.holdToConfirm };
  }
  if (b.rules) {
    s.rules = Object.fromEntries(['notifyOnVerify', 'autoEscalate', 'smsFallback', 'allowAnonymous'].map((k) => [k, !!b.rules[k]]));
    const em = Math.round(Number(b.rules.escalateMinutes ?? 5));
    if (!(em >= 1 && em <= 120)) throw bad('Auto-escalate time must be between 1 and 120 minutes');
    s.rules.escalateMinutes = em;
  }
  if (Array.isArray(b.templates)) {
    if (b.templates.length > 30) throw bad('Too many templates');
    s.templates = b.templates.map((t) => { const name = str(t.name, 60), body = str(t.body, 1000); if (!name || !body) throw bad('Every template needs a name and a message'); return { id: str(t.id, 40) || newId(), name, scope: str(t.scope, 60), title: str(t.title, 80), body }; });
  }
  if (Array.isArray(b.zones)) {
    const z = [...new Set(b.zones.map((x) => str(x, 40)).filter(Boolean))];
    if (z.length > 50) throw bad('Too many zones');
    s.zones = z;
  }
  if (Array.isArray(b.contacts)) {
    if (b.contacts.length > 30) throw bad('Too many contacts');
    s.contacts = b.contacts.map((c) => {
      const name = str(c.name, 60), number = str(c.number, 30);
      if (!name || !number) throw bad('Every contact needs a name and a number');
      return { id: str(c.id, 40) || newId(), name, number, category: c.category === 'utility' ? 'utility' : 'local', description: str(c.description, 80), show: c.show !== false };
    });
  }
  if (b.zoneInfo && typeof b.zoneInfo === 'object') {
    s.zoneInfo = {};
    for (const [k, v] of Object.entries(b.zoneInfo).slice(0, 60)) s.zoneInfo[str(k, 40)] = { captain: str(v && v.captain, 60), floodRisk: ['Low', 'Medium', 'High'].includes(v && v.floodRisk) ? v.floodRisk : '' };
  }
  if (Array.isArray(b.responders)) {
    if (b.responders.length > 200) throw bad('Too many responders');
    s.responders = b.responders.map((x) => {
      const name = str(x.name, 80); if (!name) throw bad('Every responder needs a name');
      const contact = normContact(x.contact || '');
      if (contact && !isPhone(contact)) throw bad(`“${name}”: enter a valid contact number`);
      return { id: str(x.id, 40) || newId(), name, contact, team: str(x.team, 60), role: str(x.role, 40), availability: ['available', 'oncall', 'off'].includes(x.availability) ? x.availability : 'available' };
    });
  }
  if (Array.isArray(b.teams)) {
    if (b.teams.length > 30) throw bad('Too many teams');
    s.teams = b.teams.map((t) => { const name = str(t.name, 60); if (!name) throw bad('Every team needs a name'); return { id: str(t.id, 40) || newId(), name, note: str(t.note, 80) }; });
  }
  if (b.escalation && Array.isArray(b.escalation.targets)) {
    if (b.escalation.targets.length > 20) throw bad('Too many escalation contacts');
    s.escalation = { targets: b.escalation.targets.map((t) => { const name = str(t.name, 60); if (!name) throw bad('Every escalation contact needs a name'); return { id: str(t.id, 40) || newId(), name, note: str(t.note, 80) }; }) };
  }
  return s;
}

// ------------------------------------------------------------------ routes
const routes = [];
const route = (method, pattern, auth, handler, opts = {}) => routes.push({ ...opts, method, re: new RegExp('^' + pattern.replace(/:(\w+)/g, '(?<$1>[^/]+)') + '$'), auth, handler });

// ---- public
route('GET', '/api/health', null, () => ({ ok: true }));
route('GET', '/api/config', null, () => ({
  barangay: db.settings.barangay, sos: db.settings.sos, mapCenter: db.settings.mapCenter,
  zones: db.settings.zones, allowAnonymous: db.settings.rules.allowAnonymous,
  contacts: db.settings.contacts.filter((c) => c.show), reportTypes: REPORT_TYPES,
  emailReset: mailer.enabled(),
}));
route('GET', '/api/announcements', null, () => db.announcements.slice().sort((a, b) => b.createdAt.localeCompare(a.createdAt)));
route('GET', '/api/centers', null, () => db.centers);

route('POST', '/api/auth/register', null, async ({ body, ip }) => {
  limit('registerIp', ip);
  const pw = typeof body.password === 'string' ? body.password : '';
  if (pw.length < 8 || pw.length > 100) throw bad('Password must be 8–100 characters');
  const u = newUser(body, 'resident');
  u.passwordHash = await hashPw(pw);
  db.users.push(u);
  log(`New resident registered: ${fullName(u)}`, 'user');
  return { token: issueToken(u.id), user: pubUser(u) };
});
route('POST', '/api/auth/login', null, async ({ body, ip }) => {
  const contact = normContact(body.contact), pw = typeof body.password === 'string' ? body.password.slice(0, 200) : '';
  limit('loginIp', ip);
  // Wrong-password lockouts are per phone+number, so a stranger can't lock a resident out from their own phone,
  // plus a much higher cap on one number from anywhere (stops distributed guessing).
  const key = `${ip}|${contact}`;
  if (!limiter.peek('loginFail', key).ok || !limiter.peek('loginFailAny', contact).ok) {
    const a = limiter.peek('loginFail', key), b = limiter.peek('loginFailAny', contact);
    throw new HttpError(429, 'Too many wrong attempts. Try again in a few minutes.', Math.max(a.retryAfter, b.retryAfter));
  }
  const u = db.users.find((x) => x.contact === contact);
  // run the hash either way so timing doesn't reveal which numbers exist
  const ok = u ? await checkPw(pw, u.passwordHash) : (await checkPw(pw, '00:00'), false);
  if (!ok) { limiter.hit('loginFail', key); limiter.hit('loginFailAny', contact); throw new HttpError(401, 'Incorrect contact number or password'); }
  limiter.reset('loginFail', key);
  return { token: issueToken(u.id), user: pubUser(u) };
});
// ------------------------------------------------------------------ forgot password (staff-assisted, no SMS/email cost)
// 1. Resident taps "Forgot password?" and enters their number -> a request appears in the admin console.
// 2. Staff check who they are (ID / call-back / in person), then press "Issue code" and read the 8-digit code to them.
// 3. Resident enters number + code + new password in the app. The code works once, for 30 minutes, with 5 tries.
const RESET_MS = 30 * 60000, EMAIL_RESET_MS = 15 * 60000, RESET_TRIES = 5;
const codeHash = (code, salt) => crypto.createHash('sha256').update(salt + ':' + code).digest('hex');
function pruneResets() {
  const t = Date.now();
  db.resets = db.resets.filter((r) => t - new Date(r.requestedAt).getTime() < 7 * 864e5 && r.status !== 'used');
}
function issueReset(userId, { digits = 8, ms = RESET_MS, via = 'staff' } = {}) {
  pruneResets();
  let r = db.resets.find((x) => x.userId === userId);
  if (!r) { r = { id: newId(), userId, requestedAt: nowIso(), status: 'pending' }; db.resets.push(r); }
  const code = String(crypto.randomInt(0, 10 ** digits)).padStart(digits, '0');
  r.salt = crypto.randomBytes(8).toString('hex'); r.codeHash = codeHash(code, r.salt);
  r.expiresAt = new Date(Date.now() + ms).toISOString(); r.attempts = 0; r.status = 'issued'; r.via = via;
  return { code, expiresAt: r.expiresAt };
}
route('POST', '/api/auth/forgot', null, ({ body, ip }) => {
  limit('forgotIp', ip);
  const contact = normContact(body.contact);
  limit('forgotContact', contact || 'none');
  const u = isPhone(contact) ? db.users.find((x) => x.contact === contact && x.role === 'resident') : null;
  if (u) {
    pruneResets();
    const old = db.resets.find((r) => r.userId === u.id);
    const dead = old && old.status === 'issued' && (Date.now() > new Date(old.expiresAt).getTime() || old.attempts >= RESET_TRIES);
    const wantsStaff = !!body.staff || !u.email || !mailer.enabled();
    if (wantsStaff) {
      // Staff-assisted path: used when there is no email on the account, email is not set up, or the resident asked for it.
      if (dead || (old && old.via === 'email')) db.resets = db.resets.filter((r) => r !== old);
      if (!old || dead || old.via === 'email') {
        db.resets.push({ id: newId(), userId: u.id, requestedAt: nowIso(), status: 'pending', via: 'staff' });
        log(`Password reset requested by ${fullName(u)}`, 'user'); save();
      }
    } else {
      const { code } = issueReset(u.id, { digits: 6, ms: EMAIL_RESET_MS, via: 'email' });
      save();
      mailer.send({
        to: u.email, subject: 'Your Emergency Hub password reset code',
        text: `Hello ${u.firstName},\n\nYour password reset code is: ${code}\n\nIt works once and expires in 15 minutes. Enter it in the app together with your new password.\n\nIf you did not ask for this, ignore this email – your password has not changed. Never share this code with anyone, including barangay staff who contact you first.\n\n– ${db.settings.barangay.name ? 'Barangay ' + db.settings.barangay.name : 'Emergency Hub'}`,
      }).catch((e) => console.error('[mail]', e.message));
      log(`Password reset code emailed to ${fullName(u)}`, 'user');
    }
  }
  // Same answer whether or not the number exists (and whichever path was used), so nobody can use this to find out who is registered.
  return { ok: true };
});
route('POST', '/api/auth/reset', null, async ({ body, ip }) => {
  limit('resetIp', ip);
  const contact = normContact(body.contact), code = str(body.code, 20).replace(/\s/g, '');
  const pw = typeof body.password === 'string' ? body.password : '';
  if (pw.length < 8 || pw.length > 100) throw bad('Password must be 8–100 characters');
  const fail = () => new HttpError(400, 'That code is not valid or has expired. Ask the barangay office for a new one.');
  const u = db.users.find((x) => x.contact === contact && x.role === 'resident');
  const r = u && db.resets.find((x) => x.userId === u.id && x.status === 'issued');
  if (!r || Date.now() > new Date(r.expiresAt).getTime() || r.attempts >= RESET_TRIES) throw fail();
  r.attempts += 1;
  const a = Buffer.from(codeHash(code, r.salt)), b = Buffer.from(r.codeHash);
  if (!/^\d{6,8}$/.test(code) || !crypto.timingSafeEqual(a, b)) {
    if (r.attempts >= RESET_TRIES) log(`Reset code for ${fullName(u)} locked after too many wrong tries`, 'user');
    save(); throw fail();
  }
  u.passwordHash = await hashPw(pw);
  db.resets = db.resets.filter((x) => x !== r);
  for (const t of Object.keys(db.sessions)) if (db.sessions[t].userId === u.id) delete db.sessions[t]; // log out every old session
  notify({ userId: u.id, kind: 'security', title: 'Your password was changed', body: 'If this was not you, tell the barangay office right away.' });
  limiter.reset('loginFailAny', contact);
  log(`${fullName(u)} reset their password`, 'user'); save();
  return { ok: true };
});
route('GET', '/api/admin/resets', 'admin', () => {
  pruneResets();
  return db.resets.filter((r) => r.via !== 'email').map((r) => {
    const u = db.users.find((x) => x.id === r.userId);
    const live = r.status === 'issued' && Date.now() < new Date(r.expiresAt).getTime() && r.attempts < RESET_TRIES;
    return u && { id: r.id, residentId: u.id, name: fullName(u), zone: u.zone, contactMasked: mask(u.contact), requestedAt: r.requestedAt,
      status: r.status === 'issued' ? (live ? 'issued' : 'expired') : 'pending', expiresAt: r.expiresAt || null };
  }).filter(Boolean).sort((a, b) => b.requestedAt.localeCompare(a.requestedAt));
});
route('POST', '/api/admin/resets/:id/issue', 'admin', ({ params, user }) => {
  const r = db.resets.find((x) => x.id === params.id);
  const u = r && db.users.find((x) => x.id === r.userId);
  if (!u) throw new HttpError(404, 'Request not found');
  limit('resetIssue', user.id);
  const out = issueReset(u.id);
  log(`${fullName(user)} issued a password reset code for ${fullName(u)}`, 'user'); save();
  return { ...out, name: fullName(u) };
});
route('POST', '/api/admin/residents/:id/reset', 'admin', ({ params, user }) => {
  const u = db.users.find((x) => x.id === params.id && x.role === 'resident');
  if (!u) throw new HttpError(404, 'Not found');
  limit('resetIssue', user.id);
  const out = issueReset(u.id);
  log(`${fullName(user)} issued a password reset code for ${fullName(u)}`, 'user'); save();
  return { ...out, name: fullName(u) };
});
route('DELETE', '/api/admin/resets/:id', 'admin', ({ params }) => {
  const i = db.resets.findIndex((x) => x.id === params.id);
  if (i < 0) throw new HttpError(404, 'Request not found');
  db.resets.splice(i, 1); save(); return { ok: true };
});
route('POST', '/api/auth/logout', 'user', ({ req }) => {
  delete db.sessions[req.headers.authorization.slice(7)]; save(); return { ok: true };
});

// ---- resident
route('GET', '/api/me', 'user', ({ user }) => pubUser(user));
route('POST', '/api/me/email', 'user', async ({ body, user }) => {
  limit('emailChange', user.id);
  const pw = typeof body.password === 'string' ? body.password.slice(0, 200) : '';
  if (!(await checkPw(pw, user.passwordHash))) throw new HttpError(403, 'Your password is not correct');
  user.email = cleanEmail(body.email);
  log(`${fullName(user)} ${user.email ? 'updated' : 'removed'} their recovery email`, 'user'); save();
  return pubUser(user);
});
route('POST', '/api/me/password', 'user', async ({ body, user }) => {
  limit('emailChange', user.id);
  const cur = typeof body.currentPassword === 'string' ? body.currentPassword.slice(0, 200) : '';
  const pw = typeof body.newPassword === 'string' ? body.newPassword : '';
  if (!(await checkPw(cur, user.passwordHash))) throw new HttpError(403, 'Your current password is not correct');
  if (user.role === 'admin') {
    if (pw.length < 10 || pw.length > 100 || !/[a-z]/.test(pw) || !/[A-Z]/.test(pw) || !/\d/.test(pw) || !/[^A-Za-z0-9]/.test(pw))
      throw bad('Use at least 10 characters with upper and lower case letters, a number and a symbol');
  } else if (pw.length < 8 || pw.length > 100) throw bad('Password must be 8–100 characters');
  if (pw === cur) throw bad('Your new password must be different from the current one');
  user.passwordHash = await hashPw(pw);
  log(`${fullName(user)} changed their password`, 'user');
  notify({ userId: user.id, kind: 'security', title: 'Your password was changed', body: 'If this was not you, tell the barangay office right away.' });
  save();
  return { ok: true };
});
route('POST', '/api/reports', 'user', ({ body, user }) => {
  // Offline-queue support: the phone sends a random clientId so a retry never files the same report twice.
  const clientId = /^[A-Za-z0-9-]{8,64}$/.test(str(body.clientId, 64)) ? str(body.clientId, 64) : '';
  if (clientId) {
    const dup = db.reports.find((x) => x.userId === user.id && x.clientId === clientId);
    if (dup) return dup;
  }
  // A retry of an already-filed report returned above without counting. New ones are limited per resident,
  // but a Critical report may use a separate reserve so a flood of small reports can never block a real emergency.
  const wantsCritical = body.urgency === 'Critical';
  const lim = limiter.hit('report', user.id);
  if (!lim.ok) {
    const crit = wantsCritical ? limiter.hit('reportCrit', user.id) : lim;
    if (!crit.ok) throw new HttpError(429, 'You have sent many reports in a short time. If this is an emergency, call the numbers shown in the app.', crit.retryAfter);
  }
  const type = str(body.type, 60);
  if (!ALL_TYPES.includes(type)) throw bad('Choose a valid incident type');
  const description = str(body.description, 1000);
  if (description.length < 3) throw bad('Add a short description');
  const urgency = URGENCIES.includes(body.urgency) ? body.urgency : 'Medium';
  const locationText = str(body.locationText, 200);
  const { lat, lng } = cleanLatLng(body.lat, body.lng);
  if (!locationText && lat === null) throw bad('Add a location (address/landmark or GPS)');
  const anonymous = !!body.anonymous && db.settings.rules.allowAnonymous;
  // Up to 3 photos, sent as base64 (the app shrinks them first). Only real JPEG/PNG files are kept.
  const rawPhotos = Array.isArray(body.photos) ? body.photos.slice(0, MAX_PHOTOS) : [];
  const photoBufs = [];
  for (const p of rawPhotos) {
    if (typeof p !== 'string') continue;
    const buf = Buffer.from(p.replace(/^data:[^,]*,/, ''), 'base64');
    if (buf.length < 100 || buf.length > MAX_PHOTO_BYTES) throw bad('Each photo must be under 1.5 MB');
    const jpg = buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff;
    const png = buf.slice(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
    if (!jpg && !png) throw bad('Photos must be JPEG or PNG images');
    photoBufs.push([buf, jpg ? 'jpg' : 'png']);
  }
  db.counters.report += 1;
  // When the phone was offline, keep the moment the resident actually filed it.
  const received = nowIso();
  let reportedAt = received;
  const t = Date.parse(body.reportedAt);
  if (!Number.isNaN(t) && t <= Date.now() + 5 * 60000 && t >= Date.now() - 7 * 864e5) reportedAt = new Date(t).toISOString();
  const late = Date.now() - new Date(reportedAt).getTime() > 60000;
  const r = {
    id: 'EH-' + String(db.counters.report).padStart(4, '0'), type, kind: kindOf(type), description, urgency,
    locationText, lat, lng, outside: outsideArea(lat, lng), anonymous, status: 'NEW', userId: user.id, assignedTo: '', clientId,
    reportedAt, createdAt: received, updatedAt: received, photos: [],
    timeline: [{ at: reportedAt, text: 'Reported by resident' }, ...(late ? [{ at: received, text: 'Received after the phone was back online' }] : [])],
  };
  if (photoBufs.length) {
    fs.mkdirSync(UPLOAD_DIR, { recursive: true });
    photoBufs.forEach(([buf, ext], i) => { const name = `${r.id}-${i + 1}.${ext}`; fs.writeFileSync(path.join(UPLOAD_DIR, name), buf); r.photos.push(name); });
  }
  db.reports.push(r);
  log(`New ${urgency.toLowerCase()} report ${r.id}: ${type}${late ? ' (filed offline)' : ''}`, 'report');
  if (late) notify({ userId: user.id, kind: 'report', title: 'Your saved report was received', body: `${r.id} (${type}) has reached the barangay.`, refId: r.id });
  save();
  return r;
}, { photoBody: true });
// Residents see progress, but not which staff member acted.
const residentView = (r) => ({ ...r, assignedTo: undefined, timeline: r.timeline.map((t) => ({ at: t.at, text: t.text.replace(/\s*\([^)]*\)$/, '') })) });
route('GET', '/api/notifications', 'user', ({ user }) => {
  const readAt = user.notifReadAt || user.createdAt;
  const all = visibleTo(user).sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  return {
    unread: all.filter((n) => n.createdAt > readAt).length,
    items: all.slice(0, 50).map((n) => ({ id: n.id, kind: n.kind, category: n.category, title: n.title, body: n.body, refId: n.refId, createdAt: n.createdAt, unread: n.createdAt > readAt })),
  };
});
route('POST', '/api/notifications/read', 'user', ({ user }) => { user.notifReadAt = nowIso(); save(); return { ok: true }; });
route('POST', '/api/devices', 'user', ({ body, user }) => {
  limit('device', user.id);
  const token = str(body.token, 4096);
  if (token.length < 20) throw bad('Invalid device token');
  for (const u of db.users) if (u.deviceTokens) u.deviceTokens = u.deviceTokens.filter((t) => t.token !== token); // a phone belongs to one account
  user.deviceTokens = [...(user.deviceTokens || []), { token, platform: str(body.platform, 20), at: nowIso() }].slice(-5);
  save();
  return { ok: true };
});
route('POST', '/api/devices/remove', 'user', ({ body, user }) => {
  const token = str(body.token, 4096);
  user.deviceTokens = (user.deviceTokens || []).filter((t) => t.token !== token); save();
  return { ok: true };
});
route('GET', '/api/photos/:name', 'user', ({ params, user }) => {
  const name = params.name;
  const m = /^(EH-\d{4,})-[123]\.(jpg|png)$/.exec(name);
  const r = m && db.reports.find((x) => x.id === m[1]);
  if (!r || !(r.photos || []).includes(name) || (user.role !== 'admin' && r.userId !== user.id)) throw new HttpError(404, 'Not found');
  let buf; try { buf = fs.readFileSync(path.join(UPLOAD_DIR, name)); } catch { throw new HttpError(404, 'Not found'); }
  return { __raw: buf, type: m[2] === 'png' ? 'image/png' : 'image/jpeg' };
});
route('GET', '/api/reports/mine', 'user', ({ user }) =>
  db.reports.filter((r) => r.userId === user.id).sort((a, b) => b.createdAt.localeCompare(a.createdAt)).map(residentView));
route('GET', '/api/reports/public', 'user', () =>
  db.reports.filter((r) => ['VERIFIED', 'DISPATCHED'].includes(r.status)).sort((a, b) => b.createdAt.localeCompare(a.createdAt))
    .map((r) => ({ id: r.id, type: r.type, kind: r.kind, urgency: r.urgency, status: r.status, locationText: r.locationText, lat: r.lat, lng: r.lng, createdAt: r.createdAt })));

// ---- admin
// ------------------------------------------------------------------ road blockages (set and cleared by the admin)
const BLOCK_REASONS = ['Flood', 'Accident', 'Road works', 'Fallen tree', 'Fire', 'Event / parade', 'Other'];
function cleanBlockage(b, existing) {
  const title = str(b.title, 120);
  if (title.length < 3) throw bad('Name the road or place that is blocked');
  const { lat, lng } = cleanLatLng(b.lat, b.lng);
  if (lat === null) throw bad('Pick the blocked spot on the map');
  const reason = BLOCK_REASONS.includes(b.reason) ? b.reason : 'Other';
  let until = '';
  if (str(b.until, 40)) {
    const t = Date.parse(b.until);
    if (Number.isNaN(t)) throw bad('Expected end time is not a valid date');
    until = new Date(t).toISOString();
  }
  return { title, reason, details: str(b.details, 300), lat, lng, until };
}
// After its expected end time a blockage stops showing to residents, but stays in the admin list until someone removes it.
const blockExpired = (x) => !!x.until && Date.now() > new Date(x.until).getTime();
const adminBlock = (x) => ({ ...x, expired: blockExpired(x) });
route('GET', '/api/blockages', 'user', () =>
  db.blockages.filter((x) => !blockExpired(x)).sort((a, b) => b.createdAt.localeCompare(a.createdAt))
    .map(({ id, title, reason, details, lat, lng, until, createdAt }) => ({ id, title, reason, details, lat, lng, until, createdAt })));
route('GET', '/api/admin/blockages', 'admin', () => db.blockages.slice().sort((a, b) => b.createdAt.localeCompare(a.createdAt)).map(adminBlock));
route('POST', '/api/admin/blockages', 'admin', ({ body, user }) => {
  limit('blockage', user.id);
  if (db.blockages.length >= 200) throw bad('Too many blockages. Remove the ones that are cleared first.');
  const x = { id: newId(), ...cleanBlockage(body), createdAt: nowIso(), createdBy: fullName(user) };
  db.blockages.push(x);
  log(`${fullName(user)} marked a road blockage: ${x.title} (${x.reason})`, 'report');
  if (body.notify) notify({ kind: 'alert', category: 'alert', title: `Road blocked: ${x.title}`, body: [x.reason, x.details].filter(Boolean).join(' – '), refId: x.id });
  save();
  return adminBlock(x);
});
route('PATCH', '/api/admin/blockages/:id', 'admin', ({ params, body, user }) => {
  limit('blockage', user.id);
  const x = db.blockages.find((y) => y.id === params.id);
  if (!x) throw new HttpError(404, 'Blockage not found');
  Object.assign(x, cleanBlockage({ ...x, ...body }));
  log(`${fullName(user)} updated the blockage: ${x.title}`, 'report'); save();
  return adminBlock(x);
});
route('DELETE', '/api/admin/blockages/:id', 'admin', ({ params, user }) => {
  limit('blockage', user.id);
  const i = db.blockages.findIndex((y) => y.id === params.id);
  if (i < 0) throw new HttpError(404, 'Blockage not found');
  const [x] = db.blockages.splice(i, 1);
  log(`${fullName(user)} cleared the blockage: ${x.title}`, 'report'); save();
  return { ok: true };
});

route('GET', '/api/admin/stats', 'admin', () => {
  const open = db.reports.filter((r) => ['NEW', 'VERIFIED', 'DISPATCHED'].includes(r.status));
  const cap = db.centers.reduce((s, c) => s + (c.capacity || 0), 0);
  const occ = db.centers.reduce((s, c) => s + (c.occupied || 0), 0);
  const statusCounts = Object.fromEntries(STATUSES.map((s) => [s, db.reports.filter((r) => r.status === s).length]));
  return {
    activeIncidents: db.reports.filter((r) => r.kind === 'incident' && ['VERIFIED', 'DISPATCHED'].includes(r.status)).length,
    pendingReports: statusCounts.NEW,
    hazardsMonitored: open.filter((r) => r.kind === 'hazard').length,
    centersOpen: db.centers.filter((c) => c.status === 'open').length,
    capacityUsedPct: cap ? Math.round((occ / cap) * 100) : 0,
    residents: db.users.filter((u) => u.role === 'resident').length,
    zoneCounts: db.users.reduce((m, u) => { if (u.role === 'resident' && u.zone) m[u.zone] = (m[u.zone] || 0) + 1; return m; }, {}),
    totalReports: db.reports.length,
    statusCounts,
    queue: open.slice().sort((a, b) => URGENCY_RANK[b.urgency] - URGENCY_RANK[a.urgency] || b.createdAt.localeCompare(a.createdAt)).slice(0, 5)
      .map((r) => ({ id: r.id, type: r.type, urgency: r.urgency, status: r.status, locationText: r.locationText, createdAt: r.createdAt })),
    activity: db.activity.slice(0, 8),
  };
});
const adminReport = (r) => { const u = db.users.find((x) => x.id === r.userId); return { ...r, reporterName: fullName(u), reporterZone: (u && u.zone) || '', reporterContactMasked: u ? mask(u.contact) : '' }; };
route('GET', '/api/admin/reports', 'admin', ({ query }) => {
  const q = (query.get('q') || '').toLowerCase(), st = query.get('status');
  return db.reports.filter((r) => (!st || r.status === st) && (!q || `${r.id} ${r.type} ${r.locationText}`.toLowerCase().includes(q)))
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt)).map(adminReport);
});
route('POST', '/api/admin/reports/:id/request-info', 'admin', ({ params, body, user }) => {
  const r = db.reports.find((x) => x.id === params.id);
  if (!r) throw new HttpError(404, 'Report not found');
  if (!['NEW', 'VERIFIED', 'DISPATCHED'].includes(r.status)) throw bad('Only open reports can be queried');
  const message = str(body.message, 160);
  if (message.length < 5) throw bad('Write a short message for the reporter');
  limit('infoRequest', user.id);
  r.timeline.push({ at: nowIso(), text: `More info requested: “${message}” (${fullName(user)})` });
  r.infoRequested = nowIso();
  r.updatedAt = nowIso();
  log(`More info requested for ${r.id}`, 'report');
  notify({ userId: r.userId, kind: 'report', title: 'The barangay needs more details', body: `About your report ${r.id}: ${message}`, refId: r.id });
  save();
  return r;
});
route('POST', '/api/admin/reports/:id/escalate', 'admin', ({ params, body, user }) => {
  const r = db.reports.find((x) => x.id === params.id);
  if (!r) throw new HttpError(404, 'Report not found');
  limit('escalate', user.id);
  const to = str(body.to, 80), reason = str(body.reason, 300);
  if (!to) throw bad('Choose who to escalate to');
  if (reason.length < 5) throw bad('Add a short reason for escalating');
  r.escalations = [...(r.escalations || []), { to, reason, at: nowIso(), by: fullName(user) }];
  r.timeline.push({ at: nowIso(), text: `Escalated to ${to}: ${reason} (${fullName(user)})` });
  r.updatedAt = nowIso();
  log(`${r.id} escalated to ${to}`, 'report');
  save();
  return adminReport(r);
});
// Exports are access-logged (the admin page builds the file; the server records who exported what).
// Who viewed / exported / changed what (Settings → Data & Privacy). The log() calls write these as kind audit|export|user|settings.
route('GET', '/api/admin/access-log', 'admin', () => ({ items: db.activity.filter((a) => ['audit', 'export', 'user', 'settings'].includes(a.kind)).slice(0, 100) }));
// Latest admin-relevant events for the bell panel (newest first).
route('GET', '/api/admin/feed', 'admin', () => ({
  items: db.activity.slice(0, 30),
  pending: db.reports.filter((r) => r.status === 'NEW').length,
}));
// One search box for reports, residents and places. Phone numbers are never returned.
route('GET', '/api/admin/search', 'admin', ({ query }) => {
  const q = (query.get('q') || '').trim().toLowerCase().slice(0, 60);
  if (q.length < 2) return { reports: [], residents: [], locations: [] };
  const reports = db.reports.filter((r) => `${r.id} ${r.type} ${r.locationText} ${r.description}`.toLowerCase().includes(q))
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt)).slice(0, 5)
    .map((r) => ({ id: r.id, type: r.type, locationText: r.locationText, status: r.status }));
  const residents = db.users.filter((u) => u.role === 'resident' && `${u.firstName} ${u.lastName} ${u.address} ${u.zone}`.toLowerCase().includes(q)).slice(0, 5)
    .map((u) => ({ id: u.id, name: fullName(u), zone: u.zone || '' }));
  const counts = new Map();
  for (const r of db.reports) {
    const l = (r.locationText || '').trim();
    if (l && l.toLowerCase().includes(q)) { const c = counts.get(l) || { name: l, active: 0 }; if (['NEW', 'VERIFIED', 'DISPATCHED'].includes(r.status)) c.active++; counts.set(l, c); }
  }
  return { reports, residents, locations: [...counts.values()].slice(0, 4) };
});
route('POST', '/api/admin/log-export', 'admin', ({ body, user }) => {
  log(`${fullName(user)} exported ${str(body.what, 40) || 'data'}${str(body.reason, 80) ? ' for “' + str(body.reason, 80) + '”' : ''} (${Math.max(0, Math.min(1e6, Math.floor(Number(body.count) || 0)))} rows${str(body.format, 10) ? ', ' + str(body.format, 10) : ''})`, 'export');
  save();
  return { ok: true };
});
route('PATCH', '/api/admin/reports/:id', 'admin', ({ params, body, user }) => {
  const r = db.reports.find((x) => x.id === params.id);
  if (!r) throw new HttpError(404, 'Report not found');
  if (body.status !== undefined) {
    if (!STATUSES.includes(body.status)) throw bad('Invalid status');
    if (body.status === 'REJECTED' && body.status !== r.status && !str(body.reason, 80)) throw bad('Choose a reason for rejecting this report');
    if (body.status !== r.status) {
      r.status = body.status;
      if (body.status === 'REJECTED') { r.rejectReason = str(body.reason, 80); r.rejectNote = str(body.note, 300); }
      if (body.status === 'DISPATCHED') {
        if (str(body.team, 60)) { r.assignedTo = str(body.team, 60); r.timeline.push({ at: nowIso(), text: `Assigned to ${r.assignedTo}` }); }
        if (str(body.instructions, 300)) r.timeline.push({ at: nowIso(), text: `Instructions: ${str(body.instructions, 300)}` });
      }
      if (body.status === 'RESOLVED') {
        const outcome = str(body.outcome, 60), note = str(body.note, 300);
        if (!note) throw bad('Add a short note before resolving.');
        r.resolution = { outcome, note, at: nowIso(), by: fullName(user) };
        r.timeline.push({ at: nowIso(), text: `${outcome || 'Resolved'}: ${note}` });
      }
      const label = { VERIFIED: 'Verified by admin', DISPATCHED: 'Responders dispatched', RESOLVED: 'Marked resolved', REJECTED: 'Rejected', NEW: 'Reopened' }[body.status];
      r.timeline.push({ at: nowIso(), text: `${label} (${fullName(user)})` });
      log(`${r.id} ${label.toLowerCase()}`, 'report');
      const msg = {
        VERIFIED: ['Report verified', `Your report ${r.id} (${r.type}) was verified by the barangay.`],
        DISPATCHED: ['Responders on the way', `Help has been dispatched for your report ${r.id}.`],
        RESOLVED: ['Report resolved', `Your report ${r.id} (${r.type}) has been marked resolved.`],
        REJECTED: ['Report not accepted', `Your report ${r.id} could not be accepted${r.rejectReason ? ': ' + r.rejectReason : ''}.${r.rejectNote ? ' ' + r.rejectNote : ''} If it is an emergency, call ${db.settings.sos.number}.`],
      }[body.status];
      if (msg && !(body.status === 'RESOLVED' && body.notifyReporter === false)) notify({ userId: r.userId, kind: 'report', title: msg[0], body: msg[1], refId: r.id });
      if (body.status === 'VERIFIED' && db.settings.rules.notifyOnVerify) {
        notify({ kind: 'alert', title: `${r.type} reported${r.locationText ? ' – ' + r.locationText : ''}`,
          body: 'Verified by the barangay. Stay clear of the area and follow official advisories.', refId: r.id });
      }
    }
  }
  if (body.onSite === true && !r.onSiteAt && r.status === 'DISPATCHED') {
    r.onSiteAt = nowIso();
    r.timeline.push({ at: r.onSiteAt, text: `Responders on site (${fullName(user)})` });
    log(`${r.id} responders on site`, 'report');
  }
  if (body.assignedTo !== undefined) {
    r.assignedTo = str(body.assignedTo, 60);
    if (r.assignedTo) r.timeline.push({ at: nowIso(), text: `Assigned to ${r.assignedTo}` });
  }
  r.updatedAt = nowIso();
  save();
  return adminReport(r);
});

route('GET', '/api/admin/residents', 'admin', ({ query }) => {
  const q = (query.get('q') || '').toLowerCase();
  const page = Math.max(1, parseInt(query.get('page'), 10) || 1);
  const size = Math.min(100, Math.max(1, parseInt(query.get('pageSize'), 10) || 10));
  const zoneQ = query.get('zone') || '', vulnQ = query.get('vulnerability') || '';
  const all = db.users.filter((u) => u.role === 'resident' && (!q || `${fullName(u)} ${u.address} ${u.zone} ${u.contact}`.toLowerCase().includes(q))
    && (!zoneQ || u.zone === zoneQ) && (!vulnQ || (vulnQ === 'any' ? (u.vulnerability || []).length : vulnQ === 'none' ? !(u.vulnerability || []).length : (u.vulnerability || []).includes(vulnQ))))
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  return {
    total: all.length, page, pageSize: size,
    items: all.slice((page - 1) * size, page * size).map((u) => ({
      id: u.id, name: fullName(u), address: u.address, zone: u.zone, contactMasked: mask(u.contact), createdAt: u.createdAt,
      householdSize: u.householdSize || 0, vulnerability: u.vulnerability || [],
      reportCount: db.reports.filter((r) => r.userId === u.id).length,
    })),
  };
});
route('PATCH', '/api/admin/residents/:id', 'admin', ({ params, body, user }) => {
  limit('addResident', user.id);
  const u = db.users.find((x) => x.id === params.id && x.role === 'resident');
  if (!u) throw new HttpError(404, 'Resident not found');
  const firstName = str(body.firstName, 60) || u.firstName, lastName = str(body.lastName, 60) || u.lastName;
  const address = body.address !== undefined ? str(body.address, 200) : u.address;
  const zone = body.zone !== undefined ? str(body.zone, 40) : u.zone;
  if (!address) throw bad('Address is required');
  if (db.settings.zones.length && zone !== u.zone && !db.settings.zones.includes(zone)) throw bad('Select a valid zone');
  if (body.contact) {
    const c = normContact(body.contact);
    if (c !== u.contact) {
      if (!isPhone(c)) throw bad('Enter a valid contact number');
      if (db.users.some((x) => x.id !== u.id && x.contact === c)) throw new HttpError(409, 'That contact number is already registered');
      u.contact = c;
    }
  }
  Object.assign(u, { firstName, lastName, address, zone }, cleanWelfare({ householdSize: body.householdSize ?? u.householdSize, vulnerability: body.vulnerability ?? u.vulnerability }));
  log(`${fullName(user)} updated resident ${fullName(u)}`, 'user'); save();
  return { ok: true };
});
route('GET', '/api/admin/residents/:id/contact', 'admin', ({ params, user }) => {
  limit('reveal', user.id);
  const u = db.users.find((x) => x.id === params.id);
  if (!u) throw new HttpError(404, 'Not found');
  log(`${fullName(user)} viewed the contact number of ${fullName(u)}`, 'audit'); save();
  return { contact: u.contact };
});
route('POST', '/api/admin/residents', 'admin', async ({ body, user }) => {
  limit('addResident', user.id);
  const pw = typeof body.password === 'string' && body.password ? body.password : crypto.randomBytes(6).toString('hex');
  const u = newUser(body, 'resident');
  Object.assign(u, cleanWelfare(body));
  u.passwordHash = await hashPw(pw);
  db.users.push(u);
  log(`${fullName(user)} added resident ${fullName(u)}`, 'user'); save();
  return { user: pubUser(u), temporaryPassword: body.password ? undefined : pw };
});
route('DELETE', '/api/admin/residents/:id', 'admin', ({ params, user }) => {
  const i = db.users.findIndex((u) => u.id === params.id && u.role === 'resident');
  if (i < 0) throw new HttpError(404, 'Not found');
  const [u] = db.users.splice(i, 1);
  for (const t of Object.keys(db.sessions)) if (db.sessions[t].userId === u.id) delete db.sessions[t];
  log(`${fullName(user)} removed resident ${fullName(u)}`, 'user'); save();
  return { ok: true };
});

route('POST', '/api/admin/announcements', 'admin', ({ body, user }) => {
  limit('announcement', user.id);
  const category = ['alert', 'advisory', 'event'].includes(body.category) ? body.category : null;
  const title = str(body.title, 100), text = str(body.body, 2000);
  if (!category) throw bad('Choose a category');
  if (!title || !text) throw bad('Title and message are required');
  const a = { id: newId(), category, title, body: text, createdAt: nowIso(), author: fullName(user) };
  db.announcements.push(a);
  log(`Announcement sent: ${title}`, 'announcement');
  notify({ kind: 'announcement', category, title, body: text, refId: a.id, sendPush: body.push !== false });
  save();
  return a;
});
route('DELETE', '/api/admin/announcements/:id', 'admin', ({ params }) => {
  const i = db.announcements.findIndex((a) => a.id === params.id);
  if (i < 0) throw new HttpError(404, 'Not found');
  db.announcements.splice(i, 1); save(); return { ok: true };
});

function cleanCenter(b, existing = {}) {
  const c = { ...existing };
  if (b.name !== undefined) c.name = str(b.name, 80);
  if (b.address !== undefined) c.address = str(b.address, 200);
  if (b.capacity !== undefined) { c.capacity = Math.max(0, parseInt(b.capacity, 10) || 0); }
  if (b.occupied !== undefined) { c.occupied = Math.max(0, parseInt(b.occupied, 10) || 0); }
  if (b.status !== undefined) c.status = ['open', 'standby', 'closed'].includes(b.status) ? b.status : 'standby';
  if (b.lat !== undefined || b.lng !== undefined) { const { lat, lng } = cleanLatLng(b.lat, b.lng); c.lat = lat; c.lng = lng; }
  if (!c.name) throw bad('Name is required');
  if (c.occupied > c.capacity) throw bad('Occupied cannot exceed capacity');
  return c;
}
route('POST', '/api/admin/centers', 'admin', ({ body, user }) => {
  const c = cleanCenter({ status: 'standby', capacity: 0, occupied: 0, address: '', lat: null, lng: null, ...body }, { id: newId(), createdAt: nowIso() });
  db.centers.push(c); log(`${fullName(user)} added evacuation center ${c.name}`, 'center'); save(); return c;
});
route('PATCH', '/api/admin/centers/:id', 'admin', ({ params, body }) => {
  const i = db.centers.findIndex((c) => c.id === params.id);
  if (i < 0) throw new HttpError(404, 'Not found');
  db.centers[i] = cleanCenter(body, db.centers[i]); save(); return db.centers[i];
});
route('DELETE', '/api/admin/centers/:id', 'admin', ({ params }) => {
  const i = db.centers.findIndex((c) => c.id === params.id);
  if (i < 0) throw new HttpError(404, 'Not found');
  db.centers.splice(i, 1); save(); return { ok: true };
});

route('GET', '/api/admin/push-status', 'admin', () => ({
  enabled: push.enabled(),
  devices: db.users.reduce((n, u) => n + (u.deviceTokens || []).length, 0),
}));
route('GET', '/api/admin/settings', 'admin', () => db.settings);
route('PUT', '/api/admin/settings', 'admin', ({ body, user }) => {
  Object.assign(db.settings, cleanSettings(body));
  log(`${fullName(user)} updated settings`, 'settings'); save();
  return db.settings;
});

// ------------------------------------------------------------------ static admin console
const MIME = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.svg': 'image/svg+xml', '.png': 'image/png', '.ico': 'image/x-icon' };
const CSP = "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; font-src 'self'; " +
  "img-src 'self' data: blob: https://tile.openstreetmap.org https://*.tile.openstreetmap.org; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'";
function serveStatic(req, res, pathname) {
  if (pathname === '/' || pathname === '/admin') { res.writeHead(302, { Location: '/admin/login.html' }); return res.end(); }
  let rel = decodeURIComponent(pathname.replace(/^\/admin\/?/, '')) || 'login.html';
  const file = path.normalize(path.join(ADMIN_DIR, rel));
  if (!file.startsWith(ADMIN_DIR + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) return send(res, 404, { error: 'Not found' });
  const ext = path.extname(file);
  res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'Content-Security-Policy': CSP });
  fs.createReadStream(file).pipe(res);
}

// ------------------------------------------------------------------ server
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  const cors = { 'Access-Control-Allow-Origin': CORS_ORIGIN, 'Access-Control-Expose-Headers': 'Retry-After', 'Access-Control-Allow-Headers': 'Authorization, Content-Type', 'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS', 'Vary': 'Origin' };
  try {
    if (!url.pathname.startsWith('/api/')) {
      if (req.method !== 'GET' && req.method !== 'HEAD') return send(res, 405, { error: 'Method not allowed' });
      return serveStatic(req, res, url.pathname);
    }
    if (req.method === 'OPTIONS') { res.writeHead(204, cors); return res.end(); }
    const ip = ipOf(req);
    const who = userFromReq(req);
    if (who) limit('userAll', who.id); else limit('anonIp', ip);
    for (const r of routes) {
      if (r.method !== req.method) continue;
      const m = r.re.exec(url.pathname);
      if (!m) continue;
      const user = r.auth ? who : null;
      if (r.auth && !user) throw new HttpError(401, 'Please log in');
      if (r.auth === 'admin' && user.role !== 'admin') throw new HttpError(403, 'Admins only');
      const body = ['POST', 'PUT', 'PATCH'].includes(req.method) ? await readBody(req, (r.photoBody && req.headers.authorization) ? 7 * 1024 * 1024 : 100000) : {};
      const out = await r.handler({ req, res, ip, params: m.groups || {}, body, user, query: url.searchParams });
      if (out && out.__raw) return send(res, 200, out.__raw, { ...cors, 'Content-Type': out.type });
      return send(res, 200, out, cors);
    }
    throw new HttpError(404, 'Not found');
  } catch (e) {
    if (e && e.busy) e = new HttpError(503, 'The server is busy. Please try again in a moment.', 5);
    if (!(e instanceof HttpError)) console.error(e);
    const h = { ...cors };
    if (e.retryAfter) h['Retry-After'] = String(e.retryAfter);
    send(res, e.status || 500, { error: e.status ? e.message : 'Server error', ...(e.retryAfter ? { retryAfter: e.retryAfter } : {}) }, h);
  }
});

function ensureAdmin(force) {
  let admin = db.users.find((u) => u.role === 'admin');
  if (admin && !force) return;
  const pw = process.env.ADMIN_PASSWORD || crypto.randomBytes(9).toString('base64url');
  if (!admin) {
    admin = { id: newId(), role: 'admin', firstName: 'Barangay', lastName: 'Admin', contact: 'admin', address: '', zone: '', createdAt: nowIso() };
    db.users.push(admin);
  }
  admin.passwordHash = hashPwSync(pw);
  for (const t of Object.keys(db.sessions)) if (db.sessions[t].userId === admin.id) delete db.sessions[t];
  save();
  console.log('\n  Admin login  →  username: admin   password: ' + pw + '\n  (shown once – use `node server.js --reset-admin` to set a new one)\n');
}

async function start() {
  if (pg) {
    try { await loadFromPg(); } catch (e) { console.error('[db] Could not use the PostgreSQL database:', e.message); process.exit(1); }
  } else load();
  ensureAdmin(process.argv.includes('--reset-admin'));
  if (process.argv.includes('--reset-admin') && !process.argv.includes('--serve')) {
    if (pg) { await pg.flush(); await pg.close(); }
    process.exit(0);
  }
  server.headersTimeout = 10000; server.requestTimeout = 15000; server.keepAliveTimeout = 5000;
  server.listen(PORT, () => {
  console.log(`Emergency Hub server running:\n  Admin console  http://localhost:${PORT}/admin/\n  API            http://localhost:${PORT}/api/\n  Storage        ${pg ? 'PostgreSQL (DATABASE_URL)' : 'file ' + DATA_FILE}\n  Push           ${push.enabled() ? 'on (Firebase)' : 'off – see README to switch it on'}\n  Email codes    ${mailer.enabled() ? 'on' : 'off – password resets go through the barangay office (see README)'}`);
});
}

// Write any pending changes to PostgreSQL before the process stops.
for (const sig of ['SIGINT', 'SIGTERM']) process.on(sig, async () => { try { if (pg) { await pg.flush(); await pg.close(); } } finally { process.exit(0); } });
start();
