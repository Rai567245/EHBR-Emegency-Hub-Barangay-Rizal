'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { createLimiter, clientIp, createGate } = require('../ratelimit');

test('allows up to the limit then blocks with Retry-After', () => {
  let t = 0; const l = createLimiter({ now: () => t, overrides: { report: [3, 60] } });
  for (let i = 0; i < 3; i++) assert.ok(l.hit('report', 'u1').ok);
  const r = l.hit('report', 'u1');
  assert.ok(!r.ok); assert.ok(r.retryAfter >= 1 && r.retryAfter <= 60);
  assert.ok(l.hit('report', 'u2').ok, 'other users unaffected');
});
test('window slides: capacity returns gradually, fully after two windows', () => {
  let t = 0; const l = createLimiter({ now: () => t, overrides: { report: [10, 60] } });
  for (let i = 0; i < 10; i++) l.hit('report', 'u');
  t = 61000; assert.ok(!l.hit('report', 'u').ok, 'just after rollover most of the old window still counts');
  t = 90000; assert.ok(l.hit('report', 'u').ok, 'half the capacity is back mid-window');
  t = 300000; for (let i = 0; i < 10; i++) assert.ok(l.hit('report', 'u').ok);
});
test('peek does not count, reset clears', () => {
  const l = createLimiter({ overrides: { loginFail: [2, 60] } });
  for (let i = 0; i < 5; i++) assert.ok(l.peek('loginFail', 'k').ok);
  l.hit('loginFail', 'k'); l.hit('loginFail', 'k');
  assert.ok(!l.peek('loginFail', 'k').ok);
  l.reset('loginFail', 'k'); assert.ok(l.peek('loginFail', 'k').ok);
});
test('allowlisted keys are never limited', () => {
  const l = createLimiter({ overrides: { anonIp: [1, 60] }, allow: ['1.2.3.4'] });
  for (let i = 0; i < 20; i++) assert.ok(l.hit('anonIp', '1.2.3.4').ok);
});
test('old buckets are swept', () => {
  let t = 0; const l = createLimiter({ now: () => t });
  for (let i = 0; i < 100; i++) l.hit('anonIp', 'ip' + i);
  t = 3 * 3600 * 1000; l.hit('anonIp', 'x');
  assert.ok(l.size() < 5);
});
test('clientIp ignores X-Forwarded-For unless TRUST_PROXY is set', () => {
  const req = { socket: { remoteAddress: '::ffff:9.9.9.9' }, headers: { 'x-forwarded-for': '6.6.6.6, 7.7.7.7' } };
  assert.strictEqual(clientIp(req, 0), '9.9.9.9');
  assert.strictEqual(clientIp(req, 1), '7.7.7.7');   // the proxy appended the real peer; client-supplied 6.6.6.6 is ignored
  assert.strictEqual(clientIp({ socket: { remoteAddress: '1.1.1.1' }, headers: {} }, 1), '1.1.1.1');
});
test('gate limits concurrency and refuses an overlong queue', async () => {
  const g = createGate(2, 3); let active = 0, peak = 0;
  const job = () => g(async () => { active++; peak = Math.max(peak, active); await new Promise((r) => setTimeout(r, 20)); active--; return 1; });
  const ps = [job(), job(), job(), job(), job()];
  await assert.rejects(job(), (e) => e.busy);
  await Promise.all(ps); assert.strictEqual(peak, 2);
});
