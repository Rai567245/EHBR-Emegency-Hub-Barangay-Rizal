'use strict';
/* Shared helpers for every admin page. */
const EH = (() => {
  const TOKEN = 'ehbr_admin_token', USER = 'ehbr_admin_user';
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  function logout() {
    const t = localStorage.getItem(TOKEN);
    if (t) fetch('/api/auth/logout', { method: 'POST', headers: { Authorization: 'Bearer ' + t } }).catch(() => {});
    localStorage.removeItem(TOKEN); localStorage.removeItem(USER);
    location.href = 'login.html';
  }

  async function api(path, { method = 'GET', body, auth = true } = {}) {
    const t = localStorage.getItem(TOKEN);
    let res;
    try {
      res = await fetch('/api' + path, {
        method,
        headers: { 'Content-Type': 'application/json', ...(auth && t ? { Authorization: 'Bearer ' + t } : {}) },
        body: body === undefined ? undefined : JSON.stringify(body),
      });
    } catch { throw new Error('Cannot reach the server. Is it running?'); }
    let data = null;
    try { data = await res.json(); } catch { /* empty */ }
    if (res.status === 401 && auth) { logout(); throw new Error('Session expired'); }
    if (!res.ok) throw new Error((data && data.error) || `Request failed (${res.status})`);
    return data;
  }

  const ago = (iso) => {
    const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
    if (s < 60) return 'just now';
    if (s < 3600) return Math.floor(s / 60) + 'm ago';
    if (s < 86400) return Math.floor(s / 3600) + 'h ago';
    if (s < 86400 * 14) return Math.floor(s / 86400) + 'd ago';
    return new Date(iso).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
  };
  const when = (iso) => new Date(iso).toLocaleString(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });

  function toast(msg, type = '') {
    let box = $('.toasts');
    if (!box) { box = document.createElement('div'); box.className = 'toasts'; document.body.appendChild(box); }
    const t = document.createElement('div');
    t.className = 'toast' + (type ? ' toast--' + type : '');
    t.textContent = msg;
    box.appendChild(t);
    setTimeout(() => t.remove(), 3800);
  }
  const fail = (e) => toast(e && e.message ? e.message : String(e), 'error');

  // ---- modal (form + confirm)
  function fieldHtml(f) {
    const label = `<span>${esc(f.label)}${f.required ? ' <em>*</em>' : ''}</span>`;
    const cls = 'fld' + (f.full ? ' full' : '');
    const v = f.value ?? '';
    if (f.type === 'select') {
      return `<label class="${cls}">${label}<select name="${esc(f.name)}"${f.required ? ' required' : ''}>${(f.options || []).map((o) => {
        const val = typeof o === 'string' ? o : o.value, lab = typeof o === 'string' ? o : o.label;
        return `<option value="${esc(val)}"${String(val) === String(v) ? ' selected' : ''}>${esc(lab)}</option>`;
      }).join('')}</select></label>`;
    }
    if (f.type === 'checkbox') return `<label class="fld full chk"><input type="checkbox" name="${esc(f.name)}"${f.value ? ' checked' : ''}><span>${esc(f.label)}</span></label>`;
    if (f.type === 'textarea') return `<label class="${cls}">${label}<textarea name="${esc(f.name)}" maxlength="${f.max || 2000}"${f.required ? ' required' : ''} placeholder="${esc(f.placeholder || '')}">${esc(v)}</textarea></label>`;
    return `<label class="${cls}">${label}<input class="input" name="${esc(f.name)}" type="${f.type || 'text'}" value="${esc(v)}"${f.step ? ` step="${f.step}"` : ''}${f.min !== undefined ? ` min="${f.min}"` : ''}${f.required ? ' required' : ''} maxlength="${f.max || 200}" placeholder="${esc(f.placeholder || '')}" autocomplete="off"></label>`;
  }
  function modal({ title, sub = '', fields = [], submit = 'Save', danger = false, onSubmit, onOpen }) {
    return new Promise((resolve) => {
      const bg = document.createElement('div');
      bg.className = 'modal-backdrop';
      bg.innerHTML = `<div class="modal" role="dialog" aria-modal="true" aria-label="${esc(title)}"><h3>${esc(title)}</h3>${sub ? `<p class="modal__sub">${esc(sub)}</p>` : ''}
        <form class="form-grid" novalidate>${fields.map(fieldHtml).join('')}<p class="form-error" hidden></p>
        <div class="modal__actions"><button type="button" class="btn btn--fit" data-close>Cancel</button>
        <button type="submit" class="btn ${danger ? 'btn--danger' : 'btn--primary'} btn--fit">${esc(submit)}</button></div></form></div>`;
      document.body.appendChild(bg);
      const form = $('form', bg), errEl = $('.form-error', bg);
      const close = (val) => { document.removeEventListener('keydown', onKey); bg.remove(); resolve(val); };
      const onKey = (e) => { if (e.key === 'Escape') close(null); };
      document.addEventListener('keydown', onKey);
      bg.addEventListener('mousedown', (e) => { if (e.target === bg) close(null); });
      $('[data-close]', bg).addEventListener('click', () => close(null));
      form.addEventListener('submit', async (e) => {
        e.preventDefault();
        errEl.hidden = true;
        const values = Object.fromEntries(new FormData(form).entries());
        for (const f of fields) if (f.type === 'checkbox') values[f.name] = values[f.name] === 'on';
        for (const f of fields) if (f.required && !String(values[f.name] ?? '').trim()) { errEl.textContent = `${f.label} is required`; errEl.hidden = false; return; }
        const btn = $('[type=submit]', bg); btn.disabled = true;
        try { const out = onSubmit ? await onSubmit(values) : values; close(out === undefined ? true : out); }
        catch (err) { errEl.textContent = err.message; errEl.hidden = false; btn.disabled = false; }
      });
      if (onOpen) onOpen(bg, form);
      const first = $('input, select, textarea', form); if (first) first.focus(); else $('[type=submit]', bg).focus();
    });
  }
  const confirmBox = (title, sub, submit = 'Confirm', danger = true) => modal({ title, sub, submit, danger }).then((r) => r !== null);

  // ---- csv
  function downloadCsv(name, rows) {
    const cell = (v) => { let s = String(v ?? ''); if (/^[=+\-@\t\r]/.test(s)) s = "'" + s; return '"' + s.replace(/"/g, '""') + '"'; };
    const blob = new Blob(['\ufeff' + rows.map((r) => r.map(cell).join(',')).join('\r\n')], { type: 'text/csv;charset=utf-8' });
    const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name; document.body.appendChild(a); a.click();
    setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 500);
  }

  // ---- maps (Leaflet is vendored in /admin/vendor/leaflet)
  const COLORS = { incident: '#d32f2f', hazard: '#f59e0b', center: '#34c759', block: '#111827' };
  // Keeps the map inside the barangay's service area (centre + radiusKm). radiusKm 0/undefined = unlimited.
  function areaBounds(c) {
    if (c && c.boundary && c.boundary.length >= 3) {            // exact border: its bounding box plus 15% room
      const la = c.boundary.map((p) => p[0]), lo = c.boundary.map((p) => p[1]);
      const a = Math.min(...la), b = Math.max(...la), x = Math.min(...lo), y = Math.max(...lo), pa = (b - a) * 0.15 + 0.0005, px = (y - x) * 0.15 + 0.0005;
      return [[a - pa, x - px], [b + pa, y + px]];
    }
    if (!c || !c.radiusKm) return null;
    const r = c.radiusKm * 1.25, dLat = r / 111.32, dLng = r / (111.32 * Math.cos((c.lat * Math.PI) / 180));
    return [[c.lat - dLat, c.lng - dLng], [c.lat + dLat, c.lng + dLng]];
  }
  function makeMap(el, center, zoom = 15) {
    if (typeof L === 'undefined') { el.innerHTML = '<div class="empty"><b>Map unavailable</b>The map library did not load.</div>'; return null; }
    const bounds = areaBounds(center);
    const map = L.map(el, { zoomControl: true, attributionControl: true, ...(bounds ? { maxBounds: bounds, maxBoundsViscosity: 1, minZoom: 12 } : {}) }).setView([center.lat, center.lng], zoom);
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19, attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors' }).addTo(map);
    if (center && center.boundary && center.boundary.length >= 3) {
      const poly = L.polygon(center.boundary, { color: '#c8203c', weight: 2.5, fillColor: '#c8203c', fillOpacity: 0.05, interactive: false }).addTo(map);
      map.fitBounds(poly.getBounds(), { padding: [20, 20] });
    }
    return map;
  }
  const marker = (map, lat, lng, kind, opts = {}) =>
    L.circleMarker([lat, lng], { radius: opts.radius || 9, color: '#fff', weight: 2.5, fillColor: COLORS[kind], fillOpacity: 1 }).addTo(map);

  // ---- page chrome
  function currentUser() { try { return JSON.parse(localStorage.getItem(USER)); } catch { return null; } }

  // ---- topbar extras: notifications panel (bell) and search suggestions
  function topbarExtras() {
    const SEEN = 'ehbr_admin_seen';
    const seen = () => localStorage.getItem(SEEN) || '1970-01-01T00:00:00Z';
    const bell = $('.icon-btn[aria-label="Reports"]');
    if (bell && !bell.dataset.wired) {
      bell.dataset.wired = '1'; bell.setAttribute('aria-label', 'Notifications'); bell.removeAttribute('href'); bell.style.cursor = 'pointer';
      const panel = document.createElement('div'); panel.className = 'dd bellpanel'; panel.hidden = true; document.body.appendChild(panel);
      let items = [], tab = 'all';
      const unread = () => items.filter((i) => i.at > seen());
      const draw = () => {
        const u = unread(), list = tab === 'unread' ? u : items;
        panel.innerHTML = `<div class="dd__head"><b>Notifications</b><button type="button" data-readall>Mark all read</button></div>
          <div class="dd__tabs"><button type="button" data-tab="all" class="${tab === 'all' ? 'is-on' : ''}">All</button><button type="button" data-tab="unread" class="${tab === 'unread' ? 'is-on' : ''}">Unread (${u.length})</button></div>
          <div class="dd__list">${list.length ? list.slice(0, 12).map((i) => `<a class="dd__item${i.at > seen() ? ' is-new' : ''}" href="${/EH-\d+/.test(i.text) ? 'reports.html?q=' + encodeURIComponent(i.text.match(/EH-\d+/)[0]) : '#'}"><span>${esc(i.text)}</span><time>${esc(ago(i.at))}</time></a>`).join('') : '<p class="dd__empty">You’re all caught up.</p>'}</div>
          <a class="dd__foot" href="reports.html">View all reports</a>`;
        $('[data-readall]', panel).onclick = () => { localStorage.setItem(SEEN, new Date().toISOString()); draw(); const d = $('.bell-dot'); if (d) d.hidden = true; };
        panel.querySelectorAll('[data-tab]').forEach((b) => { b.onclick = () => { tab = b.dataset.tab; draw(); }; });
      };
      bell.addEventListener('click', async (e) => {
        e.preventDefault(); e.stopPropagation();
        if (!panel.hidden) { panel.hidden = true; return; }
        const r = bell.getBoundingClientRect(); panel.style.top = r.bottom + 8 + 'px'; panel.style.right = Math.max(8, innerWidth - r.right) + 'px';
        try { items = (await api('/admin/feed')).items; } catch { items = []; }
        draw(); panel.hidden = false;
      });
      document.addEventListener('click', (e) => { if (!panel.contains(e.target)) panel.hidden = true; });
    }
    const input = $('#globalSearch');
    if (input && !input.dataset.wired) {
      input.dataset.wired = '1';
      const host = input.closest('.search'); host.style.position = 'relative';
      const dd = document.createElement('div'); dd.className = 'dd searchpanel'; dd.hidden = true; host.appendChild(dd);
      let t = null;
      input.addEventListener('input', () => {
        clearTimeout(t); const q = input.value.trim();
        if (q.length < 2) { dd.hidden = true; return; }
        t = setTimeout(async () => {
          try {
            const r = await api('/admin/search?q=' + encodeURIComponent(q));
            const sec = (title, rows) => rows.length ? `<p class="dd__sec">${title}</p>${rows.join('')}` : '';
            const html = sec('REPORTS', r.reports.map((x) => `<a class="dd__item" href="reports.html?q=${encodeURIComponent(x.id)}"><span>${esc(x.id)} · ${esc(x.type)}<small>${esc(x.locationText || '')} · ${esc(x.status.charAt(0) + x.status.slice(1).toLowerCase())}</small></span></a>`))
              + sec('RESIDENTS', r.residents.map((x) => `<a class="dd__item" href="database.html?q=${encodeURIComponent(x.name)}"><span>${esc(x.name)}<small>${esc(x.zone || 'No zone')} · contact masked</small></span></a>`))
              + sec('LOCATIONS', r.locations.map((x) => `<a class="dd__item" href="reports.html?q=${encodeURIComponent(x.name)}"><span>${esc(x.name)}<small>${x.active} active report${x.active === 1 ? '' : 's'} nearby</small></span></a>`));
            dd.innerHTML = (html || '<p class="dd__empty">No matches.</p>') + '<p class="dd__hint">Press Enter to search all reports</p>';
            dd.hidden = false;
          } catch { dd.hidden = true; }
        }, 250);
      });
      document.addEventListener('click', (e) => { if (!host.contains(e.target)) dd.hidden = true; });
      input.addEventListener('keydown', (e) => { if (e.key === 'Escape') dd.hidden = true; });
    }
  }
  function init() {
    const u = currentUser();
    if (!localStorage.getItem(TOKEN) || !u || u.role !== 'admin') { location.href = 'login.html'; return null; }
    const name = $('.user__name'); if (name) name.textContent = `${u.firstName} ${u.lastName}`.trim();
    const sub = $('.user__place'); if (sub) sub.textContent = 'Administrator';
    const out = $('#logoutBtn'); if (out) out.addEventListener('click', async () => { if (await confirmBox('Sign out of Admin Console?', 'You will need to sign in again to manage incidents and reports. Unsent changes will be lost.', 'Sign Out', false)) logout(); });

    // ---- account menu (click the name at the bottom of the sidebar)
    const box = $('.user');
    if (box && !box.querySelector('.acct-menu')) {
      box.style.position = 'relative';
      const menu = document.createElement('div');
      menu.className = 'acct-menu'; menu.hidden = true;
      menu.innerHTML = `<div class="acct-menu__head"><b>${esc(`${u.firstName} ${u.lastName}`.trim() || 'Administrator')}</b><span>Administrator · Brgy. Rizal</span><span class="acct-menu__sub">Signed in · this device · session active</span></div>
        <a href="settings.html">Account settings</a><button type="button" data-pw>Change password</button><button type="button" data-out class="acct-menu__out">Sign out</button>`;
      box.appendChild(menu);
      const toggle = (v) => { menu.hidden = v === undefined ? !menu.hidden : !v; };
      $('.user__name', box).style.cursor = 'pointer';
      [$('.user__avatar', box), $('.user__name', box), $('.user__place', box)].forEach((el) => el && el.addEventListener('click', () => toggle()));
      document.addEventListener('click', (e) => { if (!box.contains(e.target)) menu.hidden = true; });
      $('[data-out]', menu).addEventListener('click', () => { menu.hidden = true; $('#logoutBtn').click(); });
      $('[data-pw]', menu).addEventListener('click', async () => {
        menu.hidden = true;
        const ok = await modal({
          title: 'Change password', sub: 'At least 10 characters, with upper and lower case letters, a number and a symbol (! @ #).', submit: 'Update password',
          fields: [
            { name: 'currentPassword', label: 'Current password', type: 'password', required: true, full: true },
            { name: 'newPassword', label: 'New password', type: 'password', required: true, full: true },
            { name: 'again', label: 'Confirm new password', type: 'password', required: true, full: true },
          ],
          onSubmit: async (v) => {
            if (v.newPassword !== v.again) throw new Error('Passwords do not match.');
            await api('/me/password', { method: 'POST', body: { currentPassword: v.currentPassword, newPassword: v.newPassword } });
            return true;
          },
        });
        if (ok) toast('Password updated', 'ok');
      });
    }
    const search = $('#globalSearch');
    if (search) search.addEventListener('keydown', (e) => { if (e.key === 'Enter' && search.value.trim()) location.href = 'reports.html?q=' + encodeURIComponent(search.value.trim()); });
    refreshBadge();
    topbarExtras();
    return u;
  }
  async function refreshBadge() {
    try {
      const s = await api('/admin/stats');
      const b = $('.nav__badge'); if (b) { b.textContent = s.pendingReports; b.hidden = !s.pendingReports; }
      const dot = $('.bell-dot'); if (dot) dot.hidden = !s.pendingReports;
    } catch { /* page handles its own errors */ }
  }

  return { $, $$, esc, api, ago, when, toast, fail, modal, confirmBox, downloadCsv, makeMap, marker, COLORS, init, logout, TOKEN, USER };
})();
