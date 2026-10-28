'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const fs = require('node:fs'), os = require('node:os'), path = require('node:path');

let proc, base, port = 3200 + Math.floor(Math.random() * 500);
const data = path.join(os.tmpdir(), `ehbr-${process.pid}.json`);
async function start(env = {}) {
  try { fs.unlinkSync(data); } catch {}
  proc = spawn('node', [path.join(__dirname, '..', 'server.js')], { env: { ...process.env, PORT: port, DATA_FILE: data, ADMIN_PASSWORD: 'Adm1nPass!', ...env } });
  base = `http://127.0.0.1:${port}`;
  for (let i = 0; i < 50; i++) { try { await fetch(base + '/api/health'); return; } catch { await new Promise((r) => setTimeout(r, 100)); } }
  throw new Error('server did not start');
}
const stop = () => new Promise((r) => { proc.once('exit', r); proc.kill(); });
const call = (m, p, body, tok, headers = {}) => fetch(base + p, { method: m, headers: { 'Content-Type': 'application/json', ...(tok ? { Authorization: 'Bearer ' + tok } : {}), ...headers }, body: body ? JSON.stringify(body) : undefined });
let n = 0;
const register = async (extra) => { const r = await call('POST', '/api/auth/register', { firstName: 'A', lastName: 'B', contact: '09' + String(100000000 + (++n)), address: 'x', zone: 'Zone 1', password: 'password123', ...extra }); return r; };
const rep = (o = {}) => ({ type: 'Fire', description: 'smoke seen', urgency: 'Low', locationText: 'Purok 1', ...o });

test('anonymous IP flood gets 429 + Retry-After; spoofed X-Forwarded-For does not help', async () => {
  await start({ RATE_LIMITS: JSON.stringify({ anonIp: [20, 60] }) });
  let blocked = 0, last;
  for (let i = 0; i < 40; i++) { last = await call('GET', '/api/centers', null, null, { 'X-Forwarded-For': '10.0.0.' + i }); if (last.status === 429) blocked++; }
  assert.ok(blocked >= 19, 'blocked=' + blocked);
  assert.ok(Number(last.headers.get('retry-after')) >= 1);
  assert.ok((await last.json()).retryAfter >= 1);
  await stop();
});
test('login: lockout per ip+number, registration cap, hashing does not freeze the server', async () => {
  await start({ RATE_LIMITS: JSON.stringify({ registerIp: [3, 60], loginFail: [5, 60], anonIp: [10000, 60] }) });
  for (let i = 0; i < 3; i++) assert.strictEqual((await register()).status, 200);
  assert.strictEqual((await register()).status, 429);
  const codes = [];
  for (let i = 0; i < 7; i++) codes.push((await call('POST', '/api/auth/login', { contact: '09100000001', password: 'wrong' + i })).status);
  assert.deepStrictEqual(codes, [401, 401, 401, 401, 401, 429, 429]);
  // even the right password is refused while locked (that's the point)
  assert.strictEqual((await call('POST', '/api/auth/login', { contact: '09100000001', password: 'password123' })).status, 429);
  // another number is unaffected
  assert.strictEqual((await call('POST', '/api/auth/login', { contact: '09100000002', password: 'password123' })).status, 200);
  // event loop stays responsive while many hashes run
  const logins = Array.from({ length: 12 }, () => call('POST', '/api/auth/login', { contact: '09100000002', password: 'password123' }));
  const t0 = Date.now(); const h = await call('GET', '/api/health'); const dt = Date.now() - t0;
  await Promise.all(logins);
  assert.ok(dt < 500, 'health took ' + dt + 'ms during login burst');
  await stop();
});
test('reports: limit per resident, Critical reserve, retry of same clientId never counted', async () => {
  await start({ RATE_LIMITS: JSON.stringify({ report: [3, 60], reportCrit: [2, 60], anonIp: [10000, 60], userAll: [10000, 60] }) });
  const tok = (await (await register()).json()).token;
  const s = [];
  for (let i = 0; i < 4; i++) s.push((await call('POST', '/api/reports', rep(), tok)).status);
  assert.deepStrictEqual(s, [200, 200, 200, 429]);
  const crit = [];
  for (let i = 0; i < 3; i++) crit.push((await call('POST', '/api/reports', rep({ urgency: 'Critical' }), tok)).status);
  assert.deepStrictEqual(crit, [200, 200, 429]);
  // dedupe: filed earlier with a clientId before the limit, retried after it
  await stop();
  await start({ RATE_LIMITS: JSON.stringify({ report: [1, 60], reportCrit: [1, 60], anonIp: [10000, 60] }) });
  const t2 = (await (await register()).json()).token;
  const first = await call('POST', '/api/reports', rep({ clientId: 'abcdef-123456' }), t2);
  assert.strictEqual(first.status, 200); const id = (await first.json()).id;
  const retry = await call('POST', '/api/reports', rep({ clientId: 'abcdef-123456' }), t2);
  assert.strictEqual(retry.status, 200); assert.strictEqual((await retry.json()).id, id);
  assert.strictEqual((await call('POST', '/api/reports', rep({ clientId: 'zzzzzz-654321' }), t2)).status, 429);
  await stop();
});
test('body over 100KB is refused with 413; CORS exposes Retry-After', async () => {
  await start();
  const r = await call('POST', '/api/auth/login', { contact: 'x', password: 'y'.repeat(150000) });
  assert.strictEqual(r.status, 413);
  assert.match(r.headers.get('access-control-expose-headers') || '', /Retry-After/);
  await stop();
});
test('TRUST_PROXY=1 gives each client behind a proxy its own limit', async () => {
  await start({ TRUST_PROXY: '1', RATE_LIMITS: JSON.stringify({ anonIp: [3, 60] }) });
  const a = [], b = [];
  for (let i = 0; i < 5; i++) a.push((await call('GET', '/api/centers', null, null, { 'X-Forwarded-For': '1.1.1.1' })).status);
  for (let i = 0; i < 2; i++) b.push((await call('GET', '/api/centers', null, null, { 'X-Forwarded-For': '2.2.2.2' })).status);
  assert.deepStrictEqual(a, [200, 200, 200, 429, 429]); assert.deepStrictEqual(b, [200, 200]);
  await stop();
});

test('forgot password: request -> staff code -> reset; one-time, 5 tries, revokes sessions, no enumeration', async () => {
  await start({ RATE_LIMITS: JSON.stringify({ anonIp: [10000, 60], userAll: [10000, 60], forgotIp: [100, 60], forgotContact: [100, 60], resetIp: [100, 60], loginIp: [1000, 60] }) });
  const reg = await (await register({ contact: '09175550001' })).json();
  const old = reg.token;
  const admin = (await (await call('POST', '/api/auth/login', { contact: 'admin', password: 'Adm1nPass!' })).json()).token;
  // same answer for registered and unknown numbers
  const a = await (await call('POST', '/api/auth/forgot', { contact: '09175550001' })).json();
  const b = await (await call('POST', '/api/auth/forgot', { contact: '09990000000' })).json();
  assert.deepStrictEqual(a, b);
  await call('POST', '/api/auth/forgot', { contact: '09175550001' });   // duplicate must not create a second request
  let list = await (await call('GET', '/api/admin/resets', null, admin)).json();
  assert.strictEqual(list.length, 1); assert.strictEqual(list[0].status, 'pending');
  assert.strictEqual((await call('GET', '/api/admin/resets', null, old)).status, 403, 'residents cannot see requests');
  assert.ok(!JSON.stringify(list).includes('09175550001'), 'contact stays masked');
  // no code issued yet -> reset refused
  assert.strictEqual((await call('POST', '/api/auth/reset', { contact: '09175550001', code: '12345678', password: 'newpassword1' })).status, 400);
  const issued = await (await call('POST', `/api/admin/resets/${list[0].id}/issue`, {}, admin)).json();
  assert.match(issued.code, /^\d{8}$/);
  assert.ok(!fs.readFileSync(data, 'utf8').includes(issued.code), 'code is not stored in clear text');
  // wrong code x4 then right code still works; weak password refused
  const wrong = issued.code === '00000000' ? '11111111' : '00000000';
  for (let i = 0; i < 4; i++) assert.strictEqual((await call('POST', '/api/auth/reset', { contact: '09175550001', code: wrong, password: 'newpassword1' })).status, 400);
  assert.strictEqual((await call('POST', '/api/auth/reset', { contact: '09175550001', code: issued.code, password: 'short' })).status, 400);
  const ok = await call('POST', '/api/auth/reset', { contact: '09175550001', code: issued.code, password: 'newpassword1' });
  assert.strictEqual(ok.status, 200);
  // one-time
  assert.strictEqual((await call('POST', '/api/auth/reset', { contact: '09175550001', code: issued.code, password: 'another-pass1' })).status, 400);
  // old session dead, old password dead, new password works, resident was told
  assert.strictEqual((await call('GET', '/api/me', null, old)).status, 401);
  assert.strictEqual((await call('POST', '/api/auth/login', { contact: '09175550001', password: 'password123' })).status, 401);
  const nl = await call('POST', '/api/auth/login', { contact: '09175550001', password: 'newpassword1' });
  assert.strictEqual(nl.status, 200);
  const notes = await (await call('GET', '/api/notifications', null, (await nl.json()).token)).json();
  assert.ok(notes.items.some((n) => n.title === 'Your password was changed'));
  // 5 wrong tries lock the code, even for the right one
  const again = await (await call('POST', `/api/admin/residents/${reg.user.id}/reset`, {}, admin)).json();
  for (let i = 0; i < 5; i++) await call('POST', '/api/auth/reset', { contact: '09175550001', code: wrong, password: 'newpassword2' });
  assert.strictEqual((await call('POST', '/api/auth/reset', { contact: '09175550001', code: again.code, password: 'newpassword2' })).status, 400);
  // a locked code does not block a fresh request
  await call('POST', '/api/auth/forgot', { contact: '09175550001' });
  list = await (await call('GET', '/api/admin/resets', null, admin)).json();
  assert.strictEqual(list[0].status, 'pending');
  await stop();
});
test('forgot password requests are rate limited per number and per IP', async () => {
  await start({ RATE_LIMITS: JSON.stringify({ anonIp: [10000, 60], forgotContact: [2, 60] }) });
  const s = [];
  for (let i = 0; i < 4; i++) s.push((await call('POST', '/api/auth/forgot', { contact: '09175550009' })).status);
  assert.deepStrictEqual(s, [200, 200, 429, 429]);
  await stop();
});

// ---- email reset codes, against a fake SMTP server (TLS, self-signed)
const tls = require('node:tls'), { execFileSync } = require('node:child_process');
function fakeSmtp(port) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'smtp-'));
  execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', dir + '/k.pem', '-out', dir + '/c.pem', '-days', '1', '-subj', '/CN=localhost'], { stdio: 'ignore' });
  const mails = [];
  const srv = tls.createServer({ key: fs.readFileSync(dir + '/k.pem'), cert: fs.readFileSync(dir + '/c.pem') }, (s) => {
    s.setEncoding('utf8'); let inData = false, buf = '', cur = { raw: '' }, auth = 0;
    s.write('220 fake\r\n');
    s.on('data', (d) => {
      buf += d;
      if (inData) { if (buf.endsWith('\r\n.\r\n')) { inData = false; cur.raw = buf; mails.push(cur); cur = { raw: '' }; buf = ''; s.write('250 queued\r\n'); } return; }
      let i; while ((i = buf.indexOf('\r\n')) >= 0) {
        const l = buf.slice(0, i); buf = buf.slice(i + 2);
        if (/^EHLO/.test(l)) s.write('250-fake\r\n250 AUTH LOGIN\r\n');
        else if (l === 'AUTH LOGIN') { auth = 1; s.write('334 VXNlcm5hbWU6\r\n'); }
        else if (auth === 1) { cur.user = Buffer.from(l, 'base64').toString(); auth = 2; s.write('334 UGFzc3dvcmQ6\r\n'); }
        else if (auth === 2) { cur.pass = Buffer.from(l, 'base64').toString(); auth = 0; s.write(cur.pass === 'app-pass' ? '235 ok\r\n' : '535 bad\r\n'); }
        else if (/^MAIL FROM/.test(l)) s.write('250 ok\r\n');
        else if (/^RCPT TO:<(.+)>/.test(l)) { cur.to = /<(.+)>/.exec(l)[1]; s.write('250 ok\r\n'); }
        else if (l === 'DATA') { inData = true; s.write('354 go\r\n'); if (buf) { /* keep */ } }
        else if (l === 'QUIT') s.end('221 bye\r\n');
      }
    });
  });
  return new Promise((r) => srv.listen(port, '127.0.0.1', () => r({ srv, mails })));
}
function bodyOf(raw) {
  const [, b] = raw.split('\r\n\r\n'); return Buffer.from(b.replace(/\r\n/g, '').replace(/\.$/, ''), 'base64').toString();
}
test('email reset: code is emailed, works once; unknown number gets nothing; "ask the office" falls back to staff', async () => {
  const sp = 4400 + Math.floor(Math.random() * 400);
  const { srv, mails } = await fakeSmtp(sp);
  await start({ SMTP_HOST: '127.0.0.1', SMTP_PORT: String(sp), SMTP_USER: 'brgy@example.com', SMTP_PASS: 'app-pass', SMTP_FROM: 'Barangay <brgy@example.com>', SMTP_ALLOW_SELF_SIGNED: '1',
    RATE_LIMITS: JSON.stringify({ anonIp: [10000, 60], userAll: [10000, 60], forgotIp: [100, 60], forgotContact: [100, 60], resetIp: [100, 60], loginIp: [1000, 60] }) });
  assert.strictEqual((await (await call('GET', '/api/config')).json()).emailReset, true);
  assert.strictEqual((await register({ contact: '09175550101', email: 'not-an-email' })).status, 400);
  const u = await (await register({ contact: '09175550101', email: 'Ana@Example.com' })).json();
  assert.strictEqual(u.user.email, 'ana@example.com');
  await register({ contact: '09175550102' });                                   // no email on file
  const admin = (await (await call('POST', '/api/auth/login', { contact: 'admin', password: 'Adm1nPass!' })).json()).token;
  const wait = async (n) => { for (let i = 0; i < 40 && mails.length < n; i++) await new Promise((r) => setTimeout(r, 50)); };

  const r1 = await (await call('POST', '/api/auth/forgot', { contact: '09175550101' })).json();
  const r2 = await (await call('POST', '/api/auth/forgot', { contact: '09990000000' })).json();
  assert.deepStrictEqual(r1, r2, 'same reply either way');
  await wait(1); assert.strictEqual(mails.length, 1);
  assert.strictEqual(mails[0].to, 'ana@example.com');
  const text = bodyOf(mails[0].raw); const code = /code is: (\d{6})/.exec(text)[1];
  assert.ok(!fs.readFileSync(data, 'utf8').includes(code), 'emailed code not stored in clear text');
  assert.strictEqual((await (await call('GET', '/api/admin/resets', null, admin)).json()).length, 0, 'email path creates no staff request');
  assert.strictEqual((await call('POST', '/api/auth/reset', { contact: '09175550101', code: code === '000000' ? '111111' : '000000', password: 'newpassword1' })).status, 400);
  assert.strictEqual((await call('POST', '/api/auth/reset', { contact: '09175550101', code, password: 'newpassword1' })).status, 200);
  assert.strictEqual((await call('POST', '/api/auth/reset', { contact: '09175550101', code, password: 'newpassword2' })).status, 400, 'one-time');
  assert.strictEqual((await call('POST', '/api/auth/login', { contact: '09175550101', password: 'newpassword1' })).status, 200);
  // no email on file -> staff request; an email user can also choose staff help
  await call('POST', '/api/auth/forgot', { contact: '09175550102' });
  await call('POST', '/api/auth/forgot', { contact: '09175550101', staff: true });
  const list = await (await call('GET', '/api/admin/resets', null, admin)).json();
  assert.strictEqual(list.length, 2); assert.strictEqual(mails.length, 1, 'no extra email sent');
  // changing the email needs the password
  const tok = (await (await call('POST', '/api/auth/login', { contact: '09175550101', password: 'newpassword1' })).json()).token;
  assert.strictEqual((await call('POST', '/api/me/email', { email: 'x@y.com', password: 'wrong' }, tok)).status, 403);
  const ch = await (await call('POST', '/api/me/email', { email: 'new@example.com', password: 'newpassword1' }, tok)).json();
  assert.strictEqual(ch.email, 'new@example.com');
  await stop(); srv.close();
});
test('email reset: a failing mail server does not break the request or leak anything', async () => {
  await start({ SMTP_HOST: '127.0.0.1', SMTP_PORT: '1', SMTP_USER: 'a@b.com', SMTP_PASS: 'x', RATE_LIMITS: JSON.stringify({ anonIp: [10000, 60] }) });
  await register({ contact: '09175550201', email: 'ok@example.com' });
  const r = await call('POST', '/api/auth/forgot', { contact: '09175550201' });
  assert.strictEqual(r.status, 200); assert.deepStrictEqual(await r.json(), { ok: true });
  assert.strictEqual((await call('GET', '/api/health')).status, 200);
  await stop();
});

test('service area: radius setting validated; outside reports are flagged but still accepted', async () => {
  await start({ RATE_LIMITS: JSON.stringify({ anonIp: [10000, 60], userAll: [10000, 60], report: [100, 60] }) });
  const admin = (await (await call('POST', '/api/auth/login', { contact: 'admin', password: 'Adm1nPass!' })).json()).token;
  const tok = (await (await register()).json()).token;
  assert.strictEqual((await (await call('GET', '/api/config')).json()).mapCenter.radiusKm, 0, 'off until set');
  const near = await (await call('POST', '/api/reports', rep({ lat: 14.5600, lng: 121.0000 }), tok)).json();
  assert.strictEqual(near.outside, false, 'no area set -> nothing flagged');
  assert.strictEqual((await call('PUT', '/api/admin/settings', { mapCenter: { lat: 14.56, lng: 121.0, radiusKm: 500 } }, admin)).status, 400);
  assert.strictEqual((await call('PUT', '/api/admin/settings', { mapCenter: { lat: 14.56, lng: 121.0, radiusKm: 3 } }, admin)).status, 200);
  assert.strictEqual((await (await call('GET', '/api/config')).json()).mapCenter.radiusKm, 3);
  const inside = await (await call('POST', '/api/reports', rep({ lat: 14.5615, lng: 121.0010 }), tok)).json();    // ~0.2 km away
  const far = await call('POST', '/api/reports', rep({ lat: 14.6500, lng: 121.0000 }), tok);                       // ~10 km away
  assert.strictEqual(inside.outside, false);
  assert.strictEqual(far.status, 200, 'an emergency outside the area is never refused');
  assert.strictEqual((await far.json()).outside, true);
  const typed = await (await call('POST', '/api/reports', rep(), tok)).json();                                       // no GPS
  assert.strictEqual(typed.outside, false);
  await stop();
});

test('exact border: GeoJSON accepted, point-in-polygon flags reports, bad input refused', async () => {
  await start({ RATE_LIMITS: JSON.stringify({ anonIp: [10000, 60], userAll: [10000, 60], report: [100, 60] }) });
  const admin = (await (await call('POST', '/api/auth/login', { contact: 'admin', password: 'Adm1nPass!' })).json()).token;
  const tok = (await (await register()).json()).token;
  // a square about 1 km wide, GeoJSON order is [lng, lat]; a wide radius must be ignored once a border exists
  const gj = { type: 'FeatureCollection', features: [{ type: 'Feature', properties: {}, geometry: { type: 'Polygon', coordinates: [[[121.000, 14.560], [121.010, 14.560], [121.010, 14.570], [121.000, 14.570], [121.000, 14.560]]] } }] };
  const put = (b) => call('PUT', '/api/admin/settings', { mapCenter: { lat: 14.565, lng: 121.005, radiusKm: 50, boundary: b } }, admin);
  assert.strictEqual((await put('not json')).status, 400);
  assert.strictEqual((await put({ type: 'Point', coordinates: [1, 2] })).status, 400);
  assert.strictEqual((await put([[1, 1], [2, 2]])).status, 400, 'needs 3 points');
  const ok = await put(JSON.stringify(gj)); assert.strictEqual(ok.status, 200);
  const cfg = (await (await call('GET', '/api/config')).json()).mapCenter;
  assert.strictEqual(cfg.boundary.length, 4, 'closing point dropped'); assert.deepStrictEqual(cfg.boundary[0], [14.56, 121.0]);
  const inside = await (await call('POST', '/api/reports', rep({ lat: 14.565, lng: 121.005 }), tok)).json();
  const out = await call('POST', '/api/reports', rep({ lat: 14.575, lng: 121.005 }), tok);   // ~0.5 km north of the border, still inside the 50 km radius
  assert.strictEqual(inside.outside, false); assert.strictEqual(out.status, 200); assert.strictEqual((await out.json()).outside, true);
  assert.strictEqual((await put('')).status, 200);                                              // empty clears it -> radius applies again
  assert.deepStrictEqual((await (await call('GET', '/api/config')).json()).mapCenter.boundary, []);
  await stop();
});

test('road blockages: admin adds/edits/removes; residents see active ones; expired hidden; notify optional', async () => {
  await start({ RATE_LIMITS: JSON.stringify({ anonIp: [10000, 60], userAll: [10000, 60] }) });
  const admin = (await (await call('POST', '/api/auth/login', { contact: 'admin', password: 'Adm1nPass!' })).json()).token;
  const tok = (await (await register()).json()).token;
  assert.strictEqual((await call('POST', '/api/admin/blockages', { title: 'Rizal Ave', lat: 14.5, lng: 121 }, tok)).status, 403, 'residents cannot add');
  assert.strictEqual((await call('POST', '/api/admin/blockages', { title: 'ab', lat: 14.5, lng: 121 }, admin)).status, 400);
  assert.strictEqual((await call('POST', '/api/admin/blockages', { title: 'Rizal Ave', reason: 'Flood' }, admin)).status, 400, 'needs a location');
  const a = await (await call('POST', '/api/admin/blockages', { title: 'Rizal Ave corner 5th St', reason: 'Flood', details: 'Knee-deep water', lat: 14.536, lng: 121.062, notify: true }, admin)).json();
  assert.strictEqual(a.reason, 'Flood'); assert.strictEqual(a.expired, false);
  const gone = await (await call('POST', '/api/admin/blockages', { title: 'Old works', reason: 'Road works', lat: 14.537, lng: 121.063, until: new Date(Date.now() - 3600e3).toISOString() }, admin)).json();
  assert.strictEqual(gone.expired, true);
  const quiet = await (await call('POST', '/api/admin/blockages', { title: 'Parade route', reason: 'Event / parade', lat: 14.538, lng: 121.064 }, admin)).json();
  let mine = await (await call('GET', '/api/blockages', null, tok)).json();
  assert.deepStrictEqual(mine.map((x) => x.title).sort(), ['Parade route', 'Rizal Ave corner 5th St'], 'expired one hidden from residents');
  assert.ok(!('createdBy' in mine[0]), 'no staff names to residents');
  assert.strictEqual((await call('GET', '/api/blockages')).status, 401, 'login required');
  assert.strictEqual((await (await call('GET', '/api/admin/blockages', null, admin)).json()).length, 3, 'admin still sees the expired one');
  const notes = await (await call('GET', '/api/notifications', null, tok)).json();
  assert.strictEqual(notes.items.filter((n) => n.title.startsWith('Road blocked')).length, 1, 'only the one with notify');
  const ed = await call('PATCH', `/api/admin/blockages/${a.id}`, { details: 'Water going down', until: new Date(Date.now() + 3600e3).toISOString() }, admin);
  assert.strictEqual(ed.status, 200); assert.strictEqual((await ed.json()).details, 'Water going down');
  assert.strictEqual((await call('DELETE', `/api/admin/blockages/${a.id}`, null, tok)).status, 403);
  assert.strictEqual((await call('DELETE', `/api/admin/blockages/${a.id}`, null, admin)).status, 200);
  assert.strictEqual((await call('DELETE', `/api/admin/blockages/${a.id}`, null, admin)).status, 404);
  mine = await (await call('GET', '/api/blockages', null, tok)).json();
  assert.deepStrictEqual(mine.map((x) => x.title), ['Parade route'], 'removed one is gone for residents');
  await stop();
});

test('reject needs a reason (reporter is told); dispatch records team; password change checks current + strength', async () => {
  await start({ RATE_LIMITS: JSON.stringify({ anonIp: [10000, 60], userAll: [10000, 60] }) });
  const admin = (await (await call('POST', '/api/auth/login', { contact: 'admin', password: 'Adm1nPass!' })).json()).token;
  const tok = (await (await register()).json()).token;
  const r = await (await call('POST', '/api/reports', rep(), tok)).json();
  assert.strictEqual((await call('PATCH', `/api/admin/reports/${r.id}`, { status: 'REJECTED' }, admin)).status, 400, 'reason required');
  const ok = await call('PATCH', `/api/admin/reports/${r.id}`, { status: 'REJECTED', reason: 'Duplicate report', note: 'Already handled' }, admin);
  assert.strictEqual(ok.status, 200);
  const feed = await (await call('GET', '/api/notifications', null, tok)).json();
  const items = feed.items || feed;
  assert.ok(items.some((n) => /Duplicate report/.test(n.body)), 'reporter sees the reason');
  const r2 = await (await call('POST', '/api/reports', rep(), tok)).json();
  const d = await (await call('PATCH', `/api/admin/reports/${r2.id}`, { status: 'DISPATCHED', team: 'Fire station', instructions: 'Bring hose' }, admin)).json();
  assert.strictEqual(d.assignedTo, 'Fire station');
  assert.ok(d.timeline.some((t) => /Bring hose/.test(t.text)));
  assert.strictEqual((await call('POST', '/api/me/password', { currentPassword: 'wrong', newPassword: 'Abcdefghi1!x' }, admin)).status, 403);
  assert.strictEqual((await call('POST', '/api/me/password', { currentPassword: 'Adm1nPass!', newPassword: 'short' }, admin)).status, 400, 'admin rule');
  assert.strictEqual((await call('POST', '/api/me/password', { currentPassword: 'Adm1nPass!', newPassword: 'NewStrong#Pass9' }, admin)).status, 200);
  assert.strictEqual((await call('POST', '/api/auth/login', { contact: 'admin', password: 'NewStrong#Pass9' })).status, 200);
  assert.strictEqual((await call('POST', '/api/auth/login', { contact: 'admin', password: 'Adm1nPass!' })).status, 401);
  await stop();
});
