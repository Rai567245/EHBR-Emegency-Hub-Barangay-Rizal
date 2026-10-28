'use strict';
(async () => {
  if (!EH.init()) return;
  const { $, $$, esc, api, ago, fail, downloadCsv } = EH;
  let all = [], filter = 'ALL', selected = null, zones = [];
  const adv = { range: 'all', zone: '', photos: false, needsInfo: false };
  const advOn = () => adv.range !== 'all' || adv.zone || adv.photos || adv.needsInfo;
  const RANGES = { all: ['All time', 0], today: ['Today', 1], '7': ['Last 7 days', 7], '30': ['Last 30 days', 30] };
  const search = $('#globalSearch');
  search.value = new URLSearchParams(location.search).get('q') || '';
  search.placeholder = 'Search reports';

  const visible = () => {
    const q = search.value.trim().toLowerCase(), t = $('#fType').value, u = $('#fUrg').value;
    return all.filter((r) => (filter === 'ALL' || r.status === filter) && (!t || r.type === t) && (!u || r.urgency === u) &&
      (!q || `${r.id} ${r.type} ${r.locationText} ${r.reporterName} ${r.description}`.toLowerCase().includes(q)) &&
      (adv.range === 'all' || Date.now() - new Date(r.createdAt).getTime() <= RANGES[adv.range][1] * 864e5) &&
      (!adv.zone || r.reporterZone === adv.zone) && (!adv.photos || (r.photos || []).length) && (!adv.needsInfo || r.infoRequested));
  };

  function renderPanel() {
    const panel = $('#panel'), r = all.find((x) => x.id === selected);
    if (!r) { panel.innerHTML = '<div class="empty"><b>No report selected</b>Select a report to review it.</div>'; return; }
    panel.innerHTML = RP.render(r);
    RP.bind(panel, r, (upd) => { all[all.findIndex((x) => x.id === upd.id)] = upd; render(); });
  }
  function render() {
    const counts = { ALL: all.length };
    ['NEW', 'VERIFIED', 'DISPATCHED', 'RESOLVED', 'REJECTED'].forEach((s) => { counts[s] = all.filter((r) => r.status === s).length; });
    $$('#rpChips [data-n]').forEach((s) => { s.textContent = counts[s.dataset.n]; });
    const rows = visible();
    $('#rpBody').innerHTML = rows.map((r) => `<tr data-id="${esc(r.id)}" class="${r.id === selected ? 'is-selected' : ''}">
      <td class="id">${esc(r.id)}</td><td>${esc(r.type)}</td><td>${esc(RP.where(r))}</td>
      <td><span class="pill pill--${RP.UC[r.urgency]} pill--sm">${esc(r.urgency)}</span></td><td>${esc(ago(r.createdAt))}</td>
      <td><span class="pill pill--${RP.SC[r.status]} pill--sm pill--caps">${esc(r.status)}</span></td></tr>`).join('');
    $('#rpEmpty').innerHTML = rows.length ? '' : `<div class="empty"><b>${all.length ? 'No reports match these filters' : 'No reports yet'}</b>${all.length ? 'Try a different status or clear the filters.<br><button class="btn btn--sm btn--fit" id="clearFilters" style="margin-top:10px">Clear filters</button>' : 'Reports filed by residents in the app will show up here.'}</div>`;
    $('#advDot').hidden = !advOn();
    renderPanel();
  }

  try {
    $('#rpBody').innerHTML = Array.from({ length: 6 }, () => '<tr class="skeleton-row"><td colspan="6"><span class="skeleton"></span></td></tr>').join('');
    const [reports, cfg] = await Promise.all([api('/admin/reports'), api('/config'), RP.load()]);
    all = reports; zones = cfg.zones || [];
    const types = [...cfg.reportTypes.incident, ...cfg.reportTypes.hazard];
    $('#fType').innerHTML = '<option value="">Type: All</option>' + types.map((t) => `<option>${esc(t)}</option>`).join('');
    const want = search.value.trim().toUpperCase();
    const exact = all.find((r) => r.id === want); if (exact) selected = exact.id;
    render();
  } catch (e) { fail(e); }

  $('#rpBody').addEventListener('click', (e) => { const tr = e.target.closest('tr[data-id]'); if (tr) { selected = tr.dataset.id; render(); } });
  $$('#rpChips .chip').forEach((c) => c.addEventListener('click', () => { $$('#rpChips .chip').forEach((x) => x.classList.toggle('is-on', x === c)); filter = c.dataset.f; render(); }));
  ['#fType', '#fUrg'].forEach((s) => $(s).addEventListener('change', render));
  search.addEventListener('input', render);
  const clearAll = () => { filter = 'ALL'; $$('#rpChips .chip').forEach((x) => x.classList.toggle('is-on', x.dataset.f === 'ALL')); $('#fType').value = ''; $('#fUrg').value = ''; search.value = ''; Object.assign(adv, { range: 'all', zone: '', photos: false, needsInfo: false }); render(); };
  document.addEventListener('click', (e) => { if (e.target.id === 'clearFilters') clearAll(); });
  $('#filtersBtn').addEventListener('click', async () => {
    const out = await EH.modal({
      title: 'Filters', sub: `${visible().length} reports match right now.`, submit: 'Apply filters',
      fields: [
        { name: 'range', label: 'Date range', type: 'select', value: adv.range, options: Object.entries(RANGES).map(([v, [l]]) => ({ value: v, label: l })), full: true },
        { name: 'zone', label: 'Zone / Purok (of the reporter)', type: 'select', value: adv.zone, options: [{ value: '', label: 'All zones' }, ...zones], full: true },
        { name: 'photos', label: 'Has photos', type: 'checkbox', value: adv.photos, full: true },
        { name: 'needsInfo', label: 'Waiting for the reporter to reply (more info requested)', type: 'checkbox', value: adv.needsInfo, full: true },
      ],
    });
    if (out) { Object.assign(adv, { range: out.range, zone: out.zone, photos: out.photos, needsInfo: out.needsInfo }); render(); }
  });
  $('#exportBtn').addEventListener('click', async () => {
    const rows = visible(); if (!rows.length) return EH.toast('Nothing to export.');
    const mask = (n) => { const p = String(n || '').trim().split(/\s+/); return p.length > 1 ? `${p[0]} ${p[p.length - 1][0]}.` : p[0] || ''; };
    const COLS = { ID: (r) => r.id, Type: (r) => r.type, Urgency: (r) => r.urgency, Status: (r) => r.status, Location: (r) => r.locationText, Reported: (r) => r.createdAt, 'Assigned to': (r) => r.assignedTo, 'Reporter (masked)': (r) => mask(r.reporterName), Photos: (r) => (r.photos || []).length, Description: (r) => r.description };
    const out = await EH.modal({
      title: 'Export reports', sub: `${rows.length} reports match the current filters. Opens in Excel or Google Sheets. Exports are access-logged. Reporter names are masked; contact numbers are never included.`, submit: 'Export CSV',
      fields: Object.keys(COLS).map((c) => ({ name: c, label: c, type: 'checkbox', value: c !== 'Description' && c !== 'Reporter (masked)' })),
    });
    if (!out) return;
    const cols = Object.keys(COLS).filter((c) => out[c]);
    if (!cols.length) return EH.toast('Pick at least one column.');
    EH.downloadCsv('reports.csv', [cols, ...rows.map((r) => cols.map((c) => COLS[c](r)))]);
    api('/admin/log-export', { method: 'POST', body: { what: 'reports', count: rows.length, format: 'csv' } }).catch(() => {});
  });
})();
