'use strict';
(async () => {
  if (!EH.init()) return;
  const { $, $$, esc, api, fail, toast } = EH;
  const ico = (n) => `<svg class="icon"><use href="#${n}"/></svg>`;
  let saved = null, contacts = [], chain = [], tpls = [], zones = [], zoneInfo = {}, tab = 'general';

  const rowHtml = (c, i) => `<div class="crow" data-i="${i}">
    <input class="input crow__name-in" data-f="name" value="${esc(c.name)}" placeholder="Name (e.g. Police)" maxlength="60" aria-label="Name">
    <input class="input" data-f="number" value="${esc(c.number)}" placeholder="Number" maxlength="30" aria-label="Number" style="margin-left:0">
    <select class="select-sm" data-f="category" aria-label="Category"><option value="local"${c.category === 'local' ? ' selected' : ''}>Local</option><option value="utility"${c.category === 'utility' ? ' selected' : ''}>Utility</option></select>
    <span class="crow__show" style="margin-left:auto">Show in app</span><label class="toggle"><input type="checkbox" data-f="show"${c.show !== false ? ' checked' : ''} aria-label="Show in app"><i></i></label>
    <button class="x-btn" data-rm type="button" aria-label="Remove contact">${ico('i-trash')}</button></div>`;
  const drawContacts = () => {
    $('#contactRows').innerHTML = contacts.length ? contacts.map(rowHtml).join('') : '<div class="empty empty--sm">No contacts yet. Add the police, fire, medical and barangay numbers residents should see.</div>';
  };
  const readContacts = () => $$('#contactRows .crow').map((r, i) => ({
    id: contacts[i]?.id, name: $('[data-f=name]', r).value.trim(), number: $('[data-f=number]', r).value.trim(),
    category: $('[data-f=category]', r).value, show: $('[data-f=show]', r).checked, description: contacts[i]?.description || '' }));

  function fill(s) {
    $('#bName').value = s.barangay.name; $('#bCity').value = s.barangay.city; $('#bRegion').value = s.barangay.region; $('#bHot').value = s.barangay.hotline;
    $('#bLat').value = s.mapCenter.lat; $('#bLng').value = s.mapCenter.lng; $('#bRad').value = s.mapCenter.radiusKm ?? 0;
    $('#bBorder').value = (s.mapCenter.boundary || []).length ? JSON.stringify(s.mapCenter.boundary) : '';
    $('#sosNum').value = s.sos.number; $('#sosHold').checked = s.sos.holdToConfirm;
    $('#rNotify').checked = s.rules.notifyOnVerify; $('#rAuto').checked = s.rules.autoEscalate; $('#rSms').checked = s.rules.smsFallback; $('#rAnon').checked = s.rules.allowAnonymous;
    $('#rMin').value = s.rules.escalateMinutes ?? 5;
    contacts = s.contacts.map((c) => ({ ...c })); drawContacts();
    chain = ((s.escalation || {}).targets || []).map((t) => ({ ...t })); drawChain();
    tpls = (s.templates || []).map((t) => ({ ...t })); drawTpls();
    zones = s.zones || []; zoneInfo = s.zoneInfo || {}; drawZones();
  }
  const readChain = () => $$('#chainRows .crow').map((r, i) => ({ id: chain[i]?.id, name: $('[data-f=name]', r).value.trim(), note: $('[data-f=note]', r).value.trim() }));
  const drawChain = () => {
    $('#chainRows').innerHTML = chain.length ? chain.map((t, i) => `<div class="crow" data-i="${i}"><b style="width:22px">${i + 1}</b>
      <input class="input crow__name-in" data-f="name" value="${esc(t.name)}" placeholder="Office (e.g. City DRRMO)" maxlength="60" aria-label="Office">
      <input class="input" data-f="note" value="${esc(t.note || '')}" placeholder="When (e.g. After 5 minutes)" maxlength="80" aria-label="Note" style="margin-left:0">
      <button class="x-btn" data-up type="button" aria-label="Move up"${i ? '' : ' disabled'}>↑</button><button class="x-btn" data-rm type="button" aria-label="Remove">${ico('i-trash')}</button></div>`).join('')
      : '<div class="empty empty--sm">No offices yet. Add the City DRRMO, BFP, PNP… so admins can escalate a report to them.</div>';
  };
  const readTpls = () => $$('#tplRows .tpl').map((r, i) => ({ id: tpls[i]?.id, name: $('[data-f=name]', r).value.trim(), scope: $('[data-f=scope]', r).value.trim(), title: $('[data-f=title]', r).value.trim(), body: $('[data-f=body]', r).value.trim() }));
  const drawTpls = () => {
    $('#tplRows').innerHTML = tpls.length ? tpls.map((t, i) => `<div class="tpl" data-i="${i}" style="border:1px solid var(--line);border-radius:12px;padding:12px;display:grid;gap:8px">
      <div class="crow" style="padding:0;border:0"><input class="input crow__name-in" data-f="name" value="${esc(t.name)}" placeholder="Template name (e.g. Typhoon advisory)" maxlength="60" aria-label="Template name"><input class="input" data-f="scope" value="${esc(t.scope || '')}" placeholder="Who it is for (e.g. All zones)" maxlength="60" aria-label="Audience" style="margin-left:0"><button class="x-btn" data-rm type="button" aria-label="Remove template">${ico('i-trash')}</button></div>
      <input class="input" data-f="title" value="${esc(t.title || '')}" placeholder="Announcement title" maxlength="80" aria-label="Title"><textarea class="input" data-f="body" rows="2" maxlength="1000" placeholder="Message" aria-label="Message">${esc(t.body)}</textarea></div>`).join('')
      : '<div class="empty empty--sm">No templates yet. Save common messages (typhoon advisory, water outage…) to reuse them.</div>';
  };
  const drawZones = () => {
    $('#zonesView').innerHTML = zones.length ? `<table class="tbl"><thead><tr><th>Zone / Purok</th><th>Captain</th><th>Flood risk</th></tr></thead><tbody>${zones.map((z) => `<tr><td><b>${esc(z)}</b></td><td>${esc((zoneInfo[z] || {}).captain || '—')}</td><td>${esc((zoneInfo[z] || {}).floodRisk || '—')}</td></tr>`).join('')}</tbody></table>` : '<div class="empty empty--sm">No zones yet.</div>';
  };
  const drawLog = async () => {
    try {
      const { items } = await api('/admin/access-log');
      $('#logBody').innerHTML = items.map((a) => `<tr><td style="white-space:nowrap">${esc(EH.when ? EH.when(a.at) : a.at)}</td><td>${esc(a.text)}</td><td>${esc(a.kind)}</td></tr>`).join('');
      $('#logEmpty').innerHTML = items.length ? '' : '<div class="empty empty--sm">Nothing logged yet.</div>';
      $('#logExport').onclick = () => { EH.downloadCsv('access-log.csv', [['Time', 'Action', 'Type'], ...items.map((a) => [a.at, a.text, a.kind])]); api('/admin/log-export', { method: 'POST', body: { what: 'access log', count: items.length, format: 'csv', reason: 'Barangay records' } }).catch(() => {}); };
    } catch (e) { $('#logEmpty').innerHTML = '<div class="empty empty--sm">Could not load the log.</div>'; }
  };
  const collect = () => ({
    barangay: { name: $('#bName').value, city: $('#bCity').value, region: $('#bRegion').value, hotline: $('#bHot').value },
    mapCenter: { lat: $('#bLat').value, lng: $('#bLng').value, radiusKm: $('#bRad').value, boundary: $('#bBorder').value.trim() },
    sos: { number: $('#sosNum').value, holdToConfirm: $('#sosHold').checked },
    rules: { notifyOnVerify: $('#rNotify').checked, autoEscalate: $('#rAuto').checked, smsFallback: $('#rSms').checked, allowAnonymous: $('#rAnon').checked, escalateMinutes: $('#rMin').value },
    contacts: readContacts(),
    escalation: { targets: readChain() },
    templates: readTpls(),
  });
  // ---- validation (Save stays disabled until every error is fixed)
  const PHONE = /^(\+?[\d\s()\-]{3,20})$/;
  function validate() {
    const errs = [], put = (id, msg) => { errs.push([id, msg]); };
    if (!$('#bName').value.trim()) put('bName', 'Barangay name is required');
    if (!$('#bCity').value.trim()) put('bCity', 'City / Municipality is required');
    if (!$('#bRegion').value.trim()) put('bRegion', 'Region is required');
    const h = $('#bHot').value.trim(); if (h && (!PHONE.test(h) || h.replace(/\D/g, '').length < 7)) put('bHot', 'Enter a full number, e.g. (02) 8123 4567');
    if (!/^[\d+*#]{2,20}$/.test($('#sosNum').value.trim())) put('sosNum', 'SOS number may only contain digits, + * #');
    const m = Number($('#rMin').value); if (!(Number.isInteger(m) && m >= 1 && m <= 120)) put('rMin', 'Enter minutes from 1 to 120');
    $$('#contactRows .crow').forEach((r) => { const n = $('[data-f=number]', r), nm = $('[data-f=name]', r);
      if (!nm.value.trim()) { nm.id = nm.id || 'cn' + Math.random().toString(36).slice(2); put(nm.id, 'Contact needs a name'); }
      else if (!PHONE.test(n.value.trim()) || n.value.replace(/\D/g, '').length < 3) { n.id = n.id || 'cx' + Math.random().toString(36).slice(2); put(n.id, 'Enter a full number'); } });
    $$('#chainRows .crow [data-f=name]').forEach((n) => { if (!n.value.trim()) { n.id = n.id || 'ch' + Math.random().toString(36).slice(2); put(n.id, 'Office needs a name'); } });
    $$('#tplRows .tpl').forEach((t, i) => { const nm = $('[data-f=name]', t), b = $('[data-f=body]', t); if (!nm.value.trim() || !b.value.trim()) { nm.id = nm.id || 'tn' + i; put(nm.id, 'Template needs a name and a message'); } });
    $$('.field-err').forEach((e) => e.remove()); $$('.is-bad').forEach((e) => e.classList.remove('is-bad'));
    errs.forEach(([id, msg]) => { const el = document.getElementById(id); if (!el) return; el.classList.add('is-bad'); const sm = document.createElement('small'); sm.className = 'field-err'; sm.textContent = msg; (el.closest('.field') || el.parentNode).appendChild(sm); });
    const bar = $('#errBar'); bar.hidden = !errs.length; bar.textContent = errs.length ? `Fix ${errs.length} error${errs.length === 1 ? '' : 's'} before saving: ${[...new Set(errs.map((e) => e[1]))].slice(0, 3).join(' · ')}` : '';
    $('#save').disabled = errs.length > 0; $('#save').title = errs.length ? 'Save is disabled until errors are fixed' : '';
    return errs.length === 0;
  }
  const dirty = () => JSON.stringify(collect()) !== saved;
  const refresh = () => { validate(); $('#saveMsg').textContent = dirty() ? 'You have unsaved changes' : 'All changes saved'; };

  try { const s = await api('/admin/settings'); fill(s); saved = JSON.stringify(collect()); } catch (e) { return fail(e); }
  validate();

  const showTab = (t) => {
    tab = ['general', 'alerts', 'privacy', 'contacts', 'zones', 'account'].includes(t) ? t : 'general';
    $$('#tabs .tab').forEach((a) => a.classList.toggle('is-on', a.dataset.tab === tab));
    $$('[data-pane]').forEach((x) => { x.hidden = x.dataset.pane !== tab; });
    $('#savebar').hidden = !['general', 'alerts', 'contacts'].includes(tab);
    if (tab === 'privacy') drawLog();
  };
  $('#tabs').addEventListener('click', (e) => { const a = e.target.closest('.tab'); if (!a) return; e.preventDefault(); history.replaceState(null, '', '#' + a.dataset.tab); showTab(a.dataset.tab); });
  showTab(location.hash.slice(1));
  // leaving with unsaved edits: ask first (sidebar links, tab-bar links, logout)
  document.addEventListener('click', async (e) => {
    const a = e.target.closest('a[href]'); if (!a || a.closest('#tabs') || a.target === '_blank' || a.getAttribute('href').startsWith('#') || !dirty()) return;
    e.preventDefault(); e.stopPropagation();
    const ok = await EH.modal({ title: 'Leave without saving?', sub: 'You have unsaved changes on this page. If you leave now they will be lost.', submit: 'Leave anyway', danger: true });
    if (ok) { saved = JSON.stringify(collect()); location.href = a.href; }
  }, true);
  const form = $('#stForm');
  form.addEventListener('submit', (e) => e.preventDefault());
  form.addEventListener('input', refresh); form.addEventListener('change', refresh);
  $('#addContact').addEventListener('click', () => { contacts = readContacts(); contacts.push({ name: '', number: '', category: 'local', show: true }); drawContacts(); refresh(); });
  $('#addChain').addEventListener('click', () => { chain = readChain(); chain.push({ name: '', note: '' }); drawChain(); refresh(); });
  $('#chainRows').addEventListener('click', (e) => {
    const rm = e.target.closest('[data-rm]'), up = e.target.closest('[data-up]'); if (!rm && !up) return;
    chain = readChain(); const i = +e.target.closest('.crow').dataset.i;
    if (rm) chain.splice(i, 1); else if (i > 0) [chain[i - 1], chain[i]] = [chain[i], chain[i - 1]];
    drawChain(); refresh();
  });
  $('#addTpl').addEventListener('click', () => { tpls = readTpls(); tpls.push({ name: '', scope: '', title: '', body: '' }); drawTpls(); refresh(); });
  $('#tplRows').addEventListener('click', (e) => { const b = e.target.closest('[data-rm]'); if (!b) return; tpls = readTpls(); tpls.splice(+b.closest('.tpl').dataset.i, 1); drawTpls(); refresh(); });
  $('#contactRows').addEventListener('click', (e) => {
    const b = e.target.closest('[data-rm]'); if (!b) return;
    contacts = readContacts(); contacts.splice(+b.closest('.crow').dataset.i, 1); drawContacts(); refresh();
  });
  $('#save').addEventListener('click', async () => {
    if (!validate()) return;
    try { const s = await api('/admin/settings', { method: 'PUT', body: collect() }); fill(s); saved = JSON.stringify(collect()); refresh(); toast('Settings saved', 'ok'); }
    catch (e) { fail(e); }
  });
  const me = EH.USER && (() => { try { return JSON.parse(localStorage.getItem(EH.USER)); } catch { return null; } })();
  if (me && $('#acctName')) $('#acctName').textContent = `${me.firstName || ''} ${me.lastName || ''}`.trim();
  $('#chgPw').addEventListener('click', async () => {
    const out = await EH.modal({
      title: 'Change password', sub: 'At least 10 characters, with upper and lower case letters, a number and a symbol (! @ #).', submit: 'Update password',
      fields: [
        { name: 'currentPassword', label: 'Current password', type: 'password', required: true, full: true },
        { name: 'newPassword', label: 'New password', type: 'password', required: true, full: true },
        { name: 'confirm', label: 'Confirm new password', type: 'password', required: true, full: true }],
      onSubmit: async (v) => {
        if (v.newPassword !== v.confirm) throw new Error('Passwords do not match.');
        return api('/me/password', { method: 'POST', body: { currentPassword: v.currentPassword, newPassword: v.newPassword } });
      } });
    if (out) toast('Password updated', 'ok');
  });
  $('#discard').addEventListener('click', async () => { if (dirty() && !(await EH.confirmBox('Discard unsaved changes?', 'Your edits to Settings will be lost and the saved settings restored.', 'Discard'))) return; try { fill(await api('/admin/settings')); saved = JSON.stringify(collect()); refresh(); } catch (e) { fail(e); } });
  window.addEventListener('beforeunload', (e) => { if (dirty()) { e.preventDefault(); e.returnValue = ''; } });
})();
