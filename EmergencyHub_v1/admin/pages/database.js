'use strict';
(async () => {
  if (!EH.init()) return;
  const { $, $$, esc, api, ago, fail, toast, modal, confirmBox, downloadCsv } = EH;
  const ico = (n) => `<svg class="icon"><use href="#${n}"/></svg>`;
  let zones = [], centers = [], settings = null, zoneCounts = {}, rows = [], responders = [];
  const res = { q: new URLSearchParams(location.search).get('q') || '', page: 1, size: 10, total: 0, zone: '', vuln: '' };
  $('#resQ').value = res.q;
  const VULN = ['Senior', 'PWD', 'Infant', 'Pregnant'];

  // ------------------------------------------------------------- tabs
  function tab(name) {
    if (!['residents', 'responders', 'centers', 'zones'].includes(name)) name = 'residents';
    $$('#tabs .tab').forEach((t) => t.classList.toggle('is-on', t.dataset.tab === name));
    ['residents', 'responders', 'centers', 'zones'].forEach((n) => { $('#tab-' + n).hidden = n !== name; });
  }
  $('#tabs').addEventListener('click', (e) => { const t = e.target.closest('.tab'); if (t) { e.preventDefault(); history.replaceState(null, '', '#' + t.dataset.tab); tab(t.dataset.tab); } });
  tab(location.hash.slice(1));

  // ------------------------------------------------------------- residents
  async function loadResidents() {
    const out = await api(`/admin/residents?q=${encodeURIComponent(res.q)}&zone=${encodeURIComponent(res.zone)}&vulnerability=${encodeURIComponent(res.vuln)}&page=${res.page}&pageSize=${res.size}`);
    rows = out.items;
    res.total = out.total; $('#cRes').textContent = out.total;
    $('#resBody').innerHTML = out.items.map((u) => `<tr data-id="${esc(u.id)}" class="is-click">
      <td><div class="person"><span class="avatar">${esc(u.name.split(' ').map((w) => w[0]).join('').slice(0, 2).toUpperCase())}</span><div><b>${esc(u.name)}</b><small>${esc(u.address)}</small></div></div></td>
      <td>${esc(u.zone || '—')}</td>
      <td><span data-num>${esc(u.contactMasked)}</span> <button class="link-btn" data-reveal>Show</button></td>
      <td>${u.householdSize ? `${u.householdSize} member${u.householdSize === 1 ? '' : 's'}` : '—'}</td>
      <td>${u.vulnerability.length ? u.vulnerability.map((v) => `<span class="pill pill--amber pill--sm">${esc(v)}</span>`).join(' ') : '—'}</td>
      <td>${u.reportCount}</td><td>${esc(ago(u.createdAt))}</td>
      <td><button class="dots-btn" data-menu title="Actions" aria-label="Row actions">⋯</button></td></tr>`).join('');
    $('#resEmpty').innerHTML = out.items.length ? '' : `<div class="empty"><b>${res.q || res.zone || res.vuln ? 'No residents match your search' : 'No residents yet'}</b>${res.q ? '' : 'Residents appear here when they sign up in the app, or add one yourself.'}</div>`;
    const first = out.total ? (res.page - 1) * res.size + 1 : 0, last = Math.min(out.total, res.page * res.size);
    $('#resShown').textContent = out.total ? `Showing ${first}–${last} of ${out.total.toLocaleString()} resident${out.total === 1 ? '' : 's'}` : '';
    const pages = Math.max(1, Math.ceil(out.total / res.size));
    const btn = (label, p, on = false, dis = false) => `<button class="pg${on ? ' is-on' : ''}" data-p="${p}"${dis ? ' disabled' : ''}>${label}</button>`;
    let html = btn('‹', res.page - 1, false, res.page <= 1);
    for (let p = Math.max(1, res.page - 2); p <= Math.min(pages, res.page + 2); p++) html += btn(p, p, p === res.page);
    html += btn('›', res.page + 1, false, res.page >= pages);
    $('#resPager').innerHTML = out.total > res.size ? html : '';
  }
  // ---- password reset requests (staff-assisted: confirm identity first, then read the code to the resident)
  async function showCode(out) {
    const c = out.code.slice(0, 4) + ' ' + out.code.slice(4);
    await modal({ title: 'Reset code for ' + out.name, sub: `Code: ${c}   (valid 30 minutes, works once). Give it to the resident only after confirming who they are. It will not be shown again.`, submit: 'Done' });
  }
  async function loadResets() {
    const list = await api('/admin/resets'); const box = $('#resetPanel');
    box.hidden = !list.length;
    box.innerHTML = list.length ? `<div style="padding:12px 16px;font-weight:700">Password reset requests <em>${list.length}</em></div><table class="tbl"><tbody>${list.map((r) => `<tr data-rid="${esc(r.id)}">
      <td><b>${esc(r.name)}</b><br><small>${esc(r.zone || '')} · ${esc(r.contactMasked)}</small></td>
      <td>${esc(ago(r.requestedAt))}</td>
      <td>${r.status === 'issued' ? 'Code issued' : r.status === 'expired' ? 'Code expired' : 'Waiting for staff'}</td>
      <td style="text-align:right"><button class="btn btn--primary btn--sm" data-issue>${r.status === 'pending' ? 'Issue code' : 'New code'}</button> <button class="btn btn--sm" data-dismiss>Dismiss</button></td></tr>`).join('')}</tbody></table>` : '';
  }
  $('#resetPanel').addEventListener('click', async (e) => {
    const tr = e.target.closest('tr[data-rid]'); if (!tr) return;
    try {
      if (e.target.closest('[data-issue]')) { await showCode(await api(`/admin/resets/${encodeURIComponent(tr.dataset.rid)}/issue`, { method: 'POST', body: {} })); loadResets(); }
      else if (e.target.closest('[data-dismiss]')) { await api('/admin/resets/' + encodeURIComponent(tr.dataset.rid), { method: 'DELETE' }); loadResets(); }
    } catch (x) { fail(x); }
  });
  setInterval(() => loadResets().catch(() => {}), 30000);

  $('#resPager').addEventListener('click', (e) => { const b = e.target.closest('[data-p]'); if (b && !b.disabled) { res.page = +b.dataset.p; loadResidents().catch(fail); } });
  let t; $('#resQ').addEventListener('input', (e) => { clearTimeout(t); t = setTimeout(() => { res.q = e.target.value.trim(); res.page = 1; loadResidents().catch(fail); }, 250); });
  // ---- row menu, details drawer, add / edit
  const zoneField = (v) => zones.length ? { name: 'zone', label: 'Zone / Purok', type: 'select', options: [{ value: '', label: 'Select zone' }, ...zones], value: v || '', required: true } : { name: 'zone', label: 'Zone / Purok', max: 40, value: v || '' };
  const welfareFields = (u = {}) => [{ name: 'householdSize', label: 'Household size', type: 'number', min: 0, value: u.householdSize || '' },
    ...VULN.map((v) => ({ name: 'v_' + v, label: v, type: 'checkbox', value: (u.vulnerability || []).includes(v) }))];
  const welfare = (v) => ({ householdSize: v.householdSize, vulnerability: VULN.filter((x) => v['v_' + x]) });
  async function editResident(u) {
    const out = await modal({
      title: 'Edit resident', sub: `Editing ${u.name}. Changes are access-logged.`, submit: 'Save changes',
      fields: [{ name: 'firstName', label: 'First name', required: true, value: u.name.split(' ')[0] }, { name: 'lastName', label: 'Last name', required: true, value: u.name.split(' ').slice(1).join(' ') },
        { name: 'address', label: 'Address', required: true, value: u.address, full: true }, zoneField(u.zone), ...welfareFields(u)],
      onSubmit: (v) => api('/admin/residents/' + encodeURIComponent(u.id), { method: 'PATCH', body: { firstName: v.firstName, lastName: v.lastName, address: v.address, zone: v.zone, ...welfare(v) } }),
    });
    if (out) { toast('Resident updated', 'ok'); loadResidents(); }
  }
  async function deleteResident(u) {
    if (!(await confirmBox(`Remove ${u.name}?`, 'Their account and login will be deleted. Reports they filed are kept.', 'Remove'))) return;
    try { await api('/admin/residents/' + encodeURIComponent(u.id), { method: 'DELETE' }); toast('Resident removed', 'ok'); loadResidents(); } catch (x) { fail(x); }
  }
  async function resetCode(u) {
    if (!(await confirmBox('Issue a password reset code?', 'Do this only after you have confirmed the resident’s identity (valid ID, or a call-back to their number). Their old password keeps working until the code is used.', 'Issue code'))) return;
    try { await showCode(await api(`/admin/residents/${encodeURIComponent(u.id)}/reset`, { method: 'POST', body: {} })); loadResets(); } catch (x) { fail(x); }
  }
  function drawer(u) {
    document.querySelectorAll('.drawer-bg').forEach((d) => d.remove());
    const bg = document.createElement('div'); bg.className = 'drawer-bg';
    bg.innerHTML = `<aside class="drawer" role="dialog" aria-label="Resident details"><div class="drawer__head"><b>${esc(u.name)}</b><button type="button" data-x aria-label="Close">✕</button></div>
      <dl class="kv"><div class="kv__row"><dt>Address</dt><dd>${esc(u.address)}</dd></div><div class="kv__row"><dt>Zone / Purok</dt><dd>${esc(u.zone || '—')}</dd></div>
        <div class="kv__row"><dt>Contact</dt><dd><span data-num>${esc(u.contactMasked)}</span> <button class="link-btn" data-reveal>Reveal</button><small style="display:block;color:#9ca3af">Revealing is access-logged.</small></dd></div>
        <div class="kv__row"><dt>Household</dt><dd>${u.householdSize ? u.householdSize + ' member' + (u.householdSize === 1 ? '' : 's') : 'Not recorded'}</dd></div>
        <div class="kv__row"><dt>Vulnerability</dt><dd>${u.vulnerability.length ? u.vulnerability.map(esc).join(', ') : 'None recorded'}</dd></div>
        <div class="kv__row"><dt>Reports filed</dt><dd>${u.reportCount}</dd></div><div class="kv__row"><dt>Registered</dt><dd>${esc(ago(u.createdAt))}</dd></div></dl>
      <div class="drawer__actions"><button class="btn btn--fit" data-edit>Edit</button><button class="btn btn--fit btn--danger" data-del>Delete</button></div></aside>`;
    document.body.appendChild(bg);
    const close = () => bg.remove();
    bg.addEventListener('mousedown', (e) => { if (e.target === bg) close(); });
    bg.querySelector('[data-x]').onclick = close;
    bg.querySelector('[data-reveal]').onclick = async (e) => { try { const { contact } = await api(`/admin/residents/${encodeURIComponent(u.id)}/contact`); bg.querySelector('[data-num]').textContent = contact; e.target.remove(); } catch (x) { fail(x); } };
    bg.querySelector('[data-edit]').onclick = () => { close(); editResident(u); };
    bg.querySelector('[data-del]').onclick = () => { close(); deleteResident(u); };
  }
  function rowMenu(btn, u) {
    document.querySelectorAll('.rowmenu').forEach((m) => m.remove());
    const m = document.createElement('div'); m.className = 'dd rowmenu';
    m.innerHTML = '<button type="button" data-a="view">View details</button><button type="button" data-a="edit">Edit</button><button type="button" data-a="reset">Issue reset code</button><button type="button" data-a="del" class="is-danger">Delete</button>';
    document.body.appendChild(m);
    const r = btn.getBoundingClientRect(); m.style.top = r.bottom + 4 + 'px'; m.style.right = Math.max(8, innerWidth - r.right) + 'px'; m.style.position = 'fixed';
    m.onclick = (e) => { const a = e.target.dataset.a; m.remove(); if (a === 'view') drawer(u); else if (a === 'edit') editResident(u); else if (a === 'reset') resetCode(u); else if (a === 'del') deleteResident(u); };
    setTimeout(() => document.addEventListener('click', () => m.remove(), { once: true }), 0);
  }
  $('#resBody').addEventListener('click', async (e) => {
    const tr = e.target.closest('tr[data-id]'); if (!tr) return;
    const u = rows.find((x) => x.id === tr.dataset.id);
    if (e.target.closest('[data-menu]')) { e.stopPropagation(); rowMenu(e.target.closest('[data-menu]'), u); }
    else if (e.target.closest('[data-reveal]')) {
      try { const { contact } = await api(`/admin/residents/${encodeURIComponent(tr.dataset.id)}/contact`); tr.querySelector('[data-num]').textContent = contact; e.target.remove(); } catch (x) { fail(x); }
    } else drawer(u);
  });
  $('#resZone').addEventListener('change', (e) => { res.zone = e.target.value; res.page = 1; loadResidents().catch(fail); });
  $('#resVuln').addEventListener('change', (e) => { res.vuln = e.target.value; res.page = 1; loadResidents().catch(fail); });
  $('#resAdd').addEventListener('click', async () => {
    const out = await modal({
      title: 'Add resident', sub: 'Personal data is access-logged. Leave the password empty to generate a temporary one.', submit: 'Save resident',
      fields: [{ name: 'firstName', label: 'First name', required: true, max: 60 }, { name: 'lastName', label: 'Last name', required: true, max: 60 },
        { name: 'contact', label: 'Contact number', type: 'tel', required: true, max: 20, full: true, placeholder: '09XX XXX XXXX' }, { name: 'address', label: 'Address', required: true, full: true }, zoneField(''),
        ...welfareFields(), { name: 'password', label: 'Password (optional)', type: 'password', max: 100 }],
      onSubmit: (v) => api('/admin/residents', { method: 'POST', body: { ...v, ...welfare(v) } }),
    });
    if (!out) return;
    toast('Resident added', 'ok');
    if (out.temporaryPassword) await modal({ title: 'Temporary password', sub: `Share this with the resident securely: ${out.temporaryPassword}`, submit: 'Done' });
    loadResidents();
  });
  $('#resExport').addEventListener('click', async () => {
    const out = await modal({
      title: 'Export residents', sub: 'Exports are access-logged and must follow the Data Privacy Act of 2012. Contact numbers are always masked in exports.', submit: 'Export CSV',
      fields: [{ name: 'reason', label: 'Reason for export', type: 'select', required: true, full: true, options: [{ value: '', label: 'Choose a reason' }, 'Evacuation planning', 'Relief distribution', 'Barangay records', 'Other'] },
        { name: 'vuln', label: 'Include vulnerability tags', type: 'checkbox', value: false }, { name: 'addr', label: 'Include full addresses', type: 'checkbox', value: true }],
      onSubmit: (v) => { if (!v.reason) throw new Error('Choose a reason for the export.'); return v; },
    });
    if (!out) return;
    try {
      const head = ['Name', ...(out.addr ? ['Address'] : []), 'Zone', 'Contact (masked)', 'Household size', ...(out.vuln ? ['Vulnerability'] : []), 'Reports', 'Registered'], list = [head];
      for (let p = 1; ; p++) {
        const o = await api(`/admin/residents?q=${encodeURIComponent(res.q)}&zone=${encodeURIComponent(res.zone)}&vulnerability=${encodeURIComponent(res.vuln)}&page=${p}&pageSize=100`);
        o.items.forEach((u) => list.push([u.name, ...(out.addr ? [u.address] : []), u.zone, u.contactMasked, u.householdSize || '', ...(out.vuln ? [u.vulnerability.join('; ')] : []), u.reportCount, u.createdAt]));
        if (p * 100 >= o.total) break;
      }
      if (list.length === 1) return toast('No residents to export.');
      downloadCsv('residents.csv', list);
      api('/admin/log-export', { method: 'POST', body: { what: 'residents', count: list.length - 1, format: 'csv', reason: out.reason } }).catch(() => {});
    } catch (e) { fail(e); }
  });

  // ------------------------------------------------------------- responders (kept in Settings → responders)
  const AV = { available: ['Available', 'green'], oncall: ['On call', 'amber'], off: ['Off duty', 'gray'] };
  const rspFields = (r = {}) => [{ name: 'name', label: 'Full name', required: true, value: r.name, full: true }, { name: 'contact', label: 'Contact number', value: r.contact, placeholder: '09XX XXX XXXX' },
    (settings.teams || []).length ? { name: 'team', label: 'Team', type: 'select', options: [{ value: '', label: 'Select team' }, ...settings.teams.map((t) => t.name)], value: r.team || '' } : { name: 'team', label: 'Team', value: r.team, placeholder: 'e.g. Team A' },
    { name: 'role', label: 'Role', value: r.role, placeholder: 'e.g. Medic, Tanod' }, { name: 'availability', label: 'Availability', type: 'select', options: [{ value: 'available', label: 'Available' }, { value: 'oncall', label: 'On call' }, { value: 'off', label: 'Off duty' }], value: r.availability || 'available' }];
  const saveResponders = async (next) => { const st = await api('/admin/settings', { method: 'PUT', body: { responders: next } }); settings = st; responders = st.responders || []; drawResponders(); };
  function drawResponders() {
    $('#cRsp').textContent = responders.length;
    const q = ($('#rspQ').value || '').trim().toLowerCase();
    const list = responders.filter((r) => !q || `${r.name} ${r.team} ${r.role} ${r.contact}`.toLowerCase().includes(q));
    $('#rspBody').innerHTML = list.map((r) => `<tr data-id="${esc(r.id)}"><td><b>${esc(r.name)}</b></td><td>${esc(r.team || '—')}</td><td>${esc(r.role || '—')}</td>
      <td><span class="pill pill--${AV[r.availability][1]} pill--sm">${AV[r.availability][0]}</span></td><td>${esc(r.contact ? r.contact.slice(0, 4) + ' ••• ' + r.contact.slice(-4) : '—')}</td>
      <td><button class="dots-btn" data-edit aria-label="Edit">${ico('i-edit')}</button><button class="dots-btn" data-del aria-label="Delete" style="color:var(--danger)">${ico('i-trash')}</button></td></tr>`).join('');
    $('#rspEmpty').innerHTML = list.length ? '' : `<div class="empty"><b>${responders.length ? 'No responders match your search' : 'No responders yet'}</b>${responders.length ? '' : 'Add the people on your response teams so they can be assigned to reports.'}</div>`;
  }
  $('#rspQ').addEventListener('input', drawResponders);
  $('#rspAdd').addEventListener('click', async () => {
    const out = await modal({ title: 'Add responder', submit: 'Add responder', fields: rspFields(), onSubmit: async (v) => { await saveResponders([...responders, v]); return v; } });
    if (out) toast('Responder added', 'ok');
  });
  $('#rspBody').addEventListener('click', async (e) => {
    const tr = e.target.closest('tr[data-id]'); if (!tr) return; const r = responders.find((x) => x.id === tr.dataset.id);
    if (e.target.closest('[data-edit]')) { const out = await modal({ title: 'Edit responder', fields: rspFields(r), onSubmit: async (v) => { await saveResponders(responders.map((x) => (x.id === r.id ? { ...v, id: r.id } : x))); return v; } }); if (out) toast('Saved', 'ok'); }
    else if (e.target.closest('[data-del]')) { if (!(await confirmBox(`Remove ${r.name}?`, 'They will no longer appear in dispatch lists.', 'Remove'))) return; try { await saveResponders(responders.filter((x) => x.id !== r.id)); toast('Removed', 'ok'); } catch (x) { fail(x); } }
  });
  $('#teamsBtn').addEventListener('click', async () => {
    const out = await modal({
      title: 'Responder teams', sub: 'One team per line: “Name – note”, for example “Responder Team A – Available”. These appear when dispatching or assigning a report.', submit: 'Save teams',
      fields: [{ name: 'teams', label: 'Teams', type: 'textarea', max: 2000, full: true, value: (settings.teams || []).map((t) => (t.note ? `${t.name} – ${t.note}` : t.name)).join('\n') }],
      onSubmit: async (v) => {
        const teams = v.teams.split('\n').map((l) => l.trim()).filter(Boolean).map((l) => { const [name, ...note] = l.split(/\s+[–-]\s+/); return { name: name.trim(), note: note.join(' – ').trim() }; });
        settings = await api('/admin/settings', { method: 'PUT', body: { teams } }); return v;
      },
    });
    if (out) { toast('Teams saved', 'ok'); drawResponders(); }
  });

  // ------------------------------------------------------------- centers
  const centerFields = (c = {}) => [
    { name: 'name', label: 'Name', required: true, value: c.name, max: 80, full: true }, { name: 'address', label: 'Address / landmark', value: c.address, full: true },
    { name: 'lat', label: 'Latitude', type: 'number', step: 'any', value: c.lat ?? '' }, { name: 'lng', label: 'Longitude', type: 'number', step: 'any', value: c.lng ?? '' },
    { name: 'capacity', label: 'Capacity', type: 'number', min: 0, value: c.capacity ?? 0 }, { name: 'occupied', label: 'Currently inside', type: 'number', min: 0, value: c.occupied ?? 0 },
    { name: 'status', label: 'Status', type: 'select', options: [{ value: 'open', label: 'Open' }, { value: 'standby', label: 'Standby' }, { value: 'closed', label: 'Closed' }], value: c.status || 'standby', full: true }];
  async function loadCenters() {
    centers = await api('/centers'); $('#cCen').textContent = centers.length;
    $('#cenBody').innerHTML = centers.map((c) => {
      const pct = c.capacity ? Math.min(100, Math.round((c.occupied / c.capacity) * 100)) : 0, pill = c.status === 'open' ? 'green' : c.status === 'standby' ? 'amber' : 'gray';
      return `<tr data-id="${esc(c.id)}"><td><div class="person"><div><b>${esc(c.name)}</b><small>${esc(c.address || '')}</small></div></div></td>
        <td><div class="center"><span class="center__bar" style="margin-left:0"><span style="width:${pct}%;background:var(--green)"></span></span><span class="center__count">${c.occupied} / ${c.capacity}</span></div></td>
        <td><span class="pill pill--${pill} pill--sm">${esc(c.status)}</span></td><td>${c.lat != null ? `${c.lat.toFixed(4)}, ${c.lng.toFixed(4)}` : '<span class="muted">No pin</span>'}</td>
        <td><button class="dots-btn" data-edit aria-label="Edit">${ico('i-edit')}</button><button class="dots-btn" data-del aria-label="Delete" style="color:var(--danger)">${ico('i-trash')}</button></td></tr>`;
    }).join('');
    $('#cenEmpty').innerHTML = centers.length ? '' : '<div class="empty"><b>No evacuation centers yet</b>Add the covered court, school gym or hall residents should go to. Add coordinates to show it on the map.</div>';
  }
  $('#cenAdd').addEventListener('click', async () => {
    if (await modal({ title: 'Add evacuation center', fields: centerFields(), submit: 'Add', onSubmit: (v) => api('/admin/centers', { method: 'POST', body: v }) })) { toast('Center added', 'ok'); loadCenters(); }
  });
  $('#cenBody').addEventListener('click', async (e) => {
    const tr = e.target.closest('tr[data-id]'); if (!tr) return;
    const c = centers.find((x) => x.id === tr.dataset.id);
    if (e.target.closest('[data-edit]')) {
      if (await modal({ title: 'Edit evacuation center', fields: centerFields(c), onSubmit: (v) => api('/admin/centers/' + encodeURIComponent(c.id), { method: 'PATCH', body: v }) })) { toast('Saved', 'ok'); loadCenters(); }
    } else if (e.target.closest('[data-del]')) {
      if (!(await confirmBox(`Delete “${c.name}”?`, 'It will disappear from the resident app.', 'Delete'))) return;
      try { await api('/admin/centers/' + encodeURIComponent(c.id), { method: 'DELETE' }); toast('Deleted', 'ok'); loadCenters(); } catch (x) { fail(x); }
    }
  });

  // ------------------------------------------------------------- zones
  function drawZones() {
    $('#cZon').textContent = zones.length; drawZoneTable();
    $('#zoneList').innerHTML = zones.length ? zones.map((z, i) => `<span class="zone-tag">${esc(z)}<button data-rm="${i}" aria-label="Remove ${esc(z)}">${ico('i-x')}</button></span>`).join('') : '<div class="empty empty--sm">No zones yet.</div>';
  }
  const RISK = { Low: 'green', Medium: 'amber', High: 'red' };
  function drawZoneTable() {
    const info = (settings && settings.zoneInfo) || {};
    $('#zoneTable').innerHTML = zones.length ? `<table class="tbl"><thead><tr><th>Zone / Purok</th><th>Purok captain</th><th>Residents</th><th>Flood risk</th><th style="width:60px"></th></tr></thead><tbody>${zones.map((z) => {
      const i = info[z] || {};
      return `<tr data-z="${esc(z)}"><td><b>${esc(z)}</b></td><td>${esc(i.captain || '—')}</td><td>${zoneCounts[z] || 0}</td><td>${i.floodRisk ? `<span class="pill pill--${RISK[i.floodRisk]} pill--sm">${i.floodRisk}</span>` : '—'}</td><td><button class="dots-btn" data-zedit aria-label="Edit ${esc(z)}">${ico('i-edit')}</button></td></tr>`;
    }).join('')}</tbody></table>` : '';
  }
  $('#zoneTable').addEventListener('click', async (e) => {
    const b = e.target.closest('[data-zedit]'); if (!b) return; const z = b.closest('tr').dataset.z, cur = ((settings.zoneInfo || {})[z]) || {};
    const out = await modal({
      title: `Edit ${z}`, submit: 'Save', fields: [{ name: 'captain', label: 'Purok captain', value: cur.captain, full: true }, { name: 'floodRisk', label: 'Flood risk', type: 'select', options: [{ value: '', label: 'Not set' }, 'Low', 'Medium', 'High'], value: cur.floodRisk || '', full: true }],
      onSubmit: async (v) => { settings = await api('/admin/settings', { method: 'PUT', body: { zoneInfo: { ...(settings.zoneInfo || {}), [z]: v } } }); return v; },
    });
    if (out) { toast('Saved', 'ok'); drawZoneTable(); }
  });
  async function saveZones(next) {
    try { const s = await api('/admin/settings', { method: 'PUT', body: { zones: next } }); zones = s.zones; settings = s; drawZones(); fillZoneFilter(); } catch (e) { fail(e); }
  }
  $('#zoneForm').addEventListener('submit', (e) => { e.preventDefault(); const v = $('#zoneIn').value.trim(); if (!v) return; $('#zoneIn').value = ''; saveZones([...zones, v]); });
  $('#zoneList').addEventListener('click', (e) => { const b = e.target.closest('[data-rm]'); if (b) saveZones(zones.filter((_, i) => i !== +b.dataset.rm)); });

  function fillZoneFilter() { $('#resZone').innerHTML = '<option value="">Zone: All</option>' + zones.map((z) => `<option>${esc(z)}</option>`).join(''); $('#resZone').value = res.zone; }
  try {
    settings = await api('/admin/settings'); zones = settings.zones; responders = settings.responders || [];
    try { zoneCounts = (await api('/admin/stats')).zoneCounts || {}; } catch { /* counts are optional */ }
    drawZones(); fillZoneFilter(); drawResponders();
    await Promise.all([loadResidents(), loadCenters(), loadResets()]);
  } catch (e) { fail(e); }
})();
