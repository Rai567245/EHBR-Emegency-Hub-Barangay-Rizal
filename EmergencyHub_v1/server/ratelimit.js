'use strict';
/**
 * Tiny in-memory rate limiter (sliding-window counter). No dependencies.
 * Counts are per process; fine for one barangay server. Restarting resets them.
 */
const DEFAULTS = {
  // name: [max requests, window in seconds]
  anonIp:       [120, 60],     // every /api request from one IP, not logged in
  userAll:      [240, 60],     // every /api request from one logged-in account
  loginIp:      [40, 600],     // login attempts from one IP (many residents may share one IP on mobile data)
  loginFail:    [10, 900],     // wrong passwords for one contact number from one IP
  loginFailAny: [50, 900],     // wrong passwords for one contact number from anywhere
  registerIp:   [10, 3600],    // new accounts from one IP
  report:       [10, 600],     // reports per resident
  reportCrit:   [10, 600],     // extra allowance reserved for Critical reports
  forgotIp:     [10, 3600],    // "forgot password" requests per IP
  forgotContact:[3, 3600],     // ... and per phone number
  resetIp:      [20, 3600],    // code-entry attempts per IP
  resetIssue:   [60, 3600],    // codes an admin can issue
  emailChange:  [10, 3600],    // recovery-email changes per resident
  blockage:     [60, 3600],    // admin blockage add/edit/remove per hour
  device:       [30, 3600],    // push-token registrations per resident
  announcement: [30, 3600],    // announcements an admin can post
  infoRequest: [60, 3600],     // "request more info" messages an admin can send
  escalate: [60, 3600],
  reveal:       [60, 3600],    // "show contact number" clicks
  addResident:  [60, 3600],    // residents an admin can add
};

function parseOverrides(raw) {
  if (!raw) return {};
  try {
    const o = JSON.parse(raw), out = {};
    for (const [k, v] of Object.entries(o)) if (Array.isArray(v) && v.length === 2 && v.every((n) => Number.isFinite(n) && n > 0)) out[k] = v;
    return out;
  } catch { console.warn('RATE_LIMITS is not valid JSON – using defaults'); return {}; }
}

function createLimiter({ now = Date.now, overrides = {}, allow = [] } = {}) {
  const rules = { ...DEFAULTS, ...overrides };
  const buckets = new Map();          // `${rule}|${key}` -> { cur, prev, start }
  const allowed = new Set(allow);
  let lastSweep = now();

  function sweep(t) {
    if (t - lastSweep < 60000) return;
    lastSweep = t;
    for (const [k, b] of buckets) if (t - b.start > b.win * 2) buckets.delete(k);
    // hard cap so a flood of random keys can't eat memory
    if (buckets.size > 200000) buckets.clear();
  }

  function slot(rule, key) {
    const [max, secs] = rules[rule];
    const win = secs * 1000, t = now();
    sweep(t);
    const id = rule + '|' + key;
    let b = buckets.get(id);
    if (!b) { b = { cur: 0, prev: 0, start: t, win }; buckets.set(id, b); }
    if (t - b.start >= win) {                    // roll the window forward
      b.prev = t - b.start >= 2 * win ? 0 : b.cur;
      b.cur = 0; b.start += Math.floor((t - b.start) / win) * win;
    }
    const used = () => b.cur + b.prev * (1 - (now() - b.start) / win);
    return { b, max, win, used };
  }
  const retryFor = (s) => {
    // seconds until the weighted count drops below max (upper-bounded by the end of the window)
    const left = Math.ceil((s.win - (now() - s.b.start)) / 1000);
    return Math.max(1, left);
  };

  return {
    rules,
    /** Count one hit. Returns { ok, retryAfter }. */
    hit(rule, key, cost = 1) {
      if (allowed.has(key)) return { ok: true, retryAfter: 0 };
      const s = slot(rule, key);
      if (s.used() + cost > s.max) return { ok: false, retryAfter: retryFor(s) };
      s.b.cur += cost;
      return { ok: true, retryAfter: 0 };
    },
    /** Look without counting. */
    peek(rule, key) {
      if (allowed.has(key)) return { ok: true, retryAfter: 0 };
      const s = slot(rule, key);
      return s.used() >= s.max ? { ok: false, retryAfter: retryFor(s) } : { ok: true, retryAfter: 0 };
    },
    /** Forget a key (e.g. after a successful login). */
    reset(rule, key) { buckets.delete(rule + '|' + key); },
    size: () => buckets.size,
  };
}

/**
 * Work out the client IP. By default only the TCP address is trusted, so a
 * spoofed X-Forwarded-For can never dodge a limit. Behind a reverse proxy set
 * TRUST_PROXY=1 (number of proxies in front): the Nth address from the right
 * of X-Forwarded-For is used.
 */
function clientIp(req, trustProxy = 0) {
  const direct = (req.socket.remoteAddress || 'unknown').replace(/^::ffff:/, '');
  if (!trustProxy) return direct;
  const xff = String(req.headers['x-forwarded-for'] || '').split(',').map((s) => s.trim()).filter(Boolean);
  const ip = xff[xff.length - trustProxy];
  return (ip || direct).replace(/^::ffff:/, '');
}

/** Run at most `max` heavy jobs at once; extra jobs wait, and are refused if the line is too long. */
function createGate(max = 4, maxQueue = 50) {
  let active = 0; const q = [];
  const next = () => { while (active < max && q.length) { active++; q.shift()(); } };
  return function run(fn) {
    return new Promise((resolve, reject) => {
      if (q.length >= maxQueue) return reject(Object.assign(new Error('busy'), { busy: true }));
      q.push(() => { Promise.resolve().then(fn).then(resolve, reject).finally(() => { active--; next(); }); });
      next();
    });
  };
}

module.exports = { createLimiter, clientIp, createGate, parseOverrides, DEFAULTS };
