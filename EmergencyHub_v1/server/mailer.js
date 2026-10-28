'use strict';
/**
 * Minimal SMTP sender (no dependencies). Uses an encrypted connection from the start (port 465).
 * Works with Gmail (app password), Brevo, Mailjet, Zoho and most hosts' SMTP.
 *
 *   SMTP_HOST=smtp.gmail.com  SMTP_PORT=465  SMTP_USER=you@gmail.com  SMTP_PASS=<app password>
 *   SMTP_FROM="Barangay Rizal <you@gmail.com>"      (optional, defaults to SMTP_USER)
 */
const tls = require('tls');

const cfg = () => ({
  host: process.env.SMTP_HOST || '', port: parseInt(process.env.SMTP_PORT || '465', 10),
  user: process.env.SMTP_USER || '', pass: process.env.SMTP_PASS || '',
  from: process.env.SMTP_FROM || process.env.SMTP_USER || '',
  // only for automated tests with a self-signed certificate – never set this in real use
  selfSigned: process.env.SMTP_ALLOW_SELF_SIGNED === '1',
});
const enabled = () => { const c = cfg(); return !!(c.host && c.user && c.pass && c.from); };
const clean = (s) => String(s).replace(/[\r\n]+/g, ' ').trim();           // blocks header injection
const addr = (s) => { const m = /<([^<>]+)>/.exec(s); return clean(m ? m[1] : s); };
const b64 = (s) => Buffer.from(s, 'utf8').toString('base64');

function send({ to, subject, text }) {
  const c = cfg();
  return new Promise((resolve, reject) => {
    if (!enabled()) return reject(new Error('Email is not set up'));
    if (!/^[^\s@<>,;]+@[^\s@<>,;]+\.[^\s@<>,;]+$/.test(to)) return reject(new Error('Bad recipient'));
    const sock = tls.connect({ host: c.host, port: c.port, servername: c.host, rejectUnauthorized: !c.selfSigned });
    sock.setEncoding('utf8'); sock.setTimeout(20000, () => done(new Error('SMTP timeout')));
    let buf = '', step = 0, finished = false;
    const done = (err) => { if (finished) return; finished = true; try { sock.destroy(); } catch {} err ? reject(err) : resolve(); };
    const say = (l) => sock.write(l + '\r\n');
    const msg = [`From: ${clean(c.from)}`, `To: ${addr(to)}`, `Subject: ${clean(subject)}`, `Date: ${new Date().toUTCString()}`,
      'MIME-Version: 1.0', 'Content-Type: text/plain; charset=utf-8', 'Content-Transfer-Encoding: base64', '',
      b64(text).replace(/(.{76})/g, '$1\r\n')].join('\r\n');
    const plan = [   // [command to send after the previous reply, expected reply code]
      () => say('EHLO emergency-hub'), () => say('AUTH LOGIN'), () => say(b64(c.user)), () => say(b64(c.pass)),
      () => say(`MAIL FROM:<${addr(c.from)}>`), () => say(`RCPT TO:<${addr(to)}>`), () => say('DATA'),
      () => say(msg.replace(/^\./gm, '..') + '\r\n.'), () => say('QUIT'),
    ];
    const expect = [220, 250, 334, 334, 235, 250, 250, 354, 250, 221];
    sock.on('error', done);
    sock.on('close', () => done(step >= plan.length ? null : new Error('SMTP connection closed early')));
    sock.on('data', (d) => {
      buf += d;
      let i;
      while ((i = buf.indexOf('\r\n')) >= 0) {
        const line = buf.slice(0, i); buf = buf.slice(i + 2);
        if (/^\d{3}-/.test(line)) continue;                 // continuation of a multi-line reply
        const code = parseInt(line.slice(0, 3), 10);
        if (code !== expect[step]) return done(new Error(`SMTP error: ${line.slice(0, 120)}`));
        if (step >= plan.length) return done();
        plan[step++]();
      }
    });
  });
}
module.exports = { enabled, send };
