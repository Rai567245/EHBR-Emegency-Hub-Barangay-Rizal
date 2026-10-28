'use strict';
/**
 * Firebase Cloud Messaging (FCM v1) sender – zero dependencies.
 *
 * Switched on by putting your Firebase *service account* key next to server.js as
 * `firebase-service-account.json` (or point FCM_SERVICE_ACCOUNT at it).
 * Without that file everything else still works; push is simply off.
 */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const SA_PATH = process.env.FCM_SERVICE_ACCOUNT || path.join(__dirname, 'firebase-service-account.json');
const API_BASE = (process.env.FCM_API_BASE || 'https://fcm.googleapis.com').replace(/\/+$/, '');

let sa = null;
let cached = { token: null, exp: 0 };

function load() {
  try {
    const j = JSON.parse(fs.readFileSync(SA_PATH, 'utf8'));
    if (!j.client_email || !j.private_key || !j.project_id) throw new Error('missing client_email / private_key / project_id');
    sa = j;
  } catch (e) {
    sa = null;
    if (e.code !== 'ENOENT') console.error('[push] service account file is not usable:', e.message);
  }
}
load();

const enabled = () => sa !== null;
const b64 = (v) => Buffer.from(typeof v === 'string' ? v : JSON.stringify(v)).toString('base64url');
const clip = (s, n) => String(s || '').slice(0, n);

async function accessToken() {
  const now = Math.floor(Date.now() / 1000);
  if (cached.token && cached.exp - 60 > now) return cached.token;
  const aud = sa.token_uri || 'https://oauth2.googleapis.com/token';
  const unsigned = b64({ alg: 'RS256', typ: 'JWT' }) + '.' + b64({
    iss: sa.client_email, scope: 'https://www.googleapis.com/auth/firebase.messaging', aud, iat: now, exp: now + 3600,
  });
  const sig = crypto.createSign('RSA-SHA256').update(unsigned).sign(sa.private_key).toString('base64url');
  const res = await fetch(aud, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: unsigned + '.' + sig }),
  });
  if (!res.ok) throw new Error(`Google sign-in failed (${res.status}): ${clip(await res.text(), 200)}`);
  const j = await res.json();
  cached = { token: j.access_token, exp: now + (j.expires_in || 3600) };
  return cached.token;
}

/**
 * target: { token } for one device, or { topic } for everyone subscribed.
 * Resolves { ok } or { ok:false, dead } – `dead` means the device token is no longer valid.
 */
async function send(target, { title, body, data = {} }) {
  if (!sa) return { ok: false, skipped: true };
  const message = {
    ...target,
    notification: { title: clip(title, 100), body: clip(body, 200) },
    data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v ?? '')])),
    android: { priority: 'HIGH' },
    apns: { headers: { 'apns-priority': '10' }, payload: { aps: { sound: 'default' } } },
  };
  const res = await fetch(`${API_BASE}/v1/projects/${encodeURIComponent(sa.project_id)}/messages:send`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + (await accessToken()), 'Content-Type': 'application/json' },
    body: JSON.stringify({ message }),
  });
  if (res.ok) return { ok: true };
  const text = await res.text();
  if (res.status === 401) cached = { token: null, exp: 0 };
  console.error(`[push] FCM ${res.status}: ${clip(text, 200)}`);
  return { ok: false, status: res.status, dead: !!target.token && (res.status === 404 || /UNREGISTERED|not a valid FCM registration token/i.test(text)) };
}

module.exports = { enabled, send };
