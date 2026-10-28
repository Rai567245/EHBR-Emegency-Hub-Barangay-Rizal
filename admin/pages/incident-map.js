'use strict';
(async () => {
  if (!EH.init()) return;
  RP.load();
  const { $, $$, api, fail, makeMap, marker, esc } = EH;
  let map = null, layer = null, filter = 'all', selected = null, status = 'active', range = { key: 'all', from: null, to: null }, layers = { incident: true, hazard: true, center: true, block: true }, lastOk = null, data = { reports: [], centers: [], blocks: [], settings: null };

  function showPanel(r) {
    selected = r ? r.id : null;
    const panel = $('#panel');
    if (!r) { panel.innerHTML = '<div class="empty"><b>No report selected</b>Click a marker on the map to see its details and take action.</div>'; return; }
    panel.innerHTML = RP.render(r);
    RP.bind(panel, r, (upd) => { const i = data.reports.findIndex((x) => x.id === upd.id); if (i >= 0) data.reports[i] = upd; draw(); showPanel(upd); });
  }

  function draw() {
    const t0 = range.key === 'all' ? 0 : range.key === 'custom' ? range.from : Date.now() - ({ hour: 3600e3, day: 864e5, week: 7 * 864e5 }[range.key] || 0);
    const t1 = range.key === 'custom' ? range.to : Infinity;
    const inRange = (r) => { const t = new Date(r.createdAt).getTime(); return t >= t0 && t <= t1; };
    const statusOk = (r) => status === 'all' || (status === 'active' ? ['NEW', 'VERIFIED', 'DISPATCHED'].includes(r.status) : r.status === status);
    const open = data.reports.filter((r) => statusOk(r) && inRange(r));
    const located = open.filter((r) => r.lat != null);
    const counts = { incident: located.filter((r) => r.kind === 'incident').length, hazard: located.filter((r) => r.kind === 'hazard').length, center: data.centers.filter((c) => c.lat != null).length };
    counts.all = counts.incident + counts.hazard + counts.center;
    $$('#mapChips [data-n]').forEach((s) => { s.textContent = counts[s.dataset.n]; });
    if (!map) return;
    if (layer) layer.remove();
    layer = L.featureGroup().addTo(map);
    const pts = [];
    if (filter !== 'center') located.filter((r) => (filter === 'all' || r.kind === filter) && layers[r.kind]).forEach((r) => {
      const m = marker(layer, r.lat, r.lng, r.kind, { radius: r.id === selected ? 12 : 9 });
      m.bindTooltip(`${r.type} · ${r.locationText || ''}`); m.on('click', () => showPanel(r)); pts.push([r.lat, r.lng]);
    });
    if ((filter === 'all' || filter === 'center') && layers.center) data.centers.filter((c) => c.lat != null).forEach((c) => {
      marker(layer, c.lat, c.lng, 'center').bindTooltip(`${c.name} · ${c.status}`); pts.push([c.lat, c.lng]);
    });
    // road blockages are always shown (dark markers) so staff can see which roads are closed
    if (layers.block) data.blocks.filter((b) => !b.expired).forEach((b) => {
      marker(layer, b.lat, b.lng, 'block', { radius: 10 }).bindTooltip(`Road blocked: ${b.title} · ${b.reason}`).on('click', () => { location.href = 'blockages.html'; });
    });
    if (!draw.fitted && pts.length) { map.fitBounds(pts, { padding: [50, 50], maxZoom: 16 }); draw.fitted = true; }
    const noGps = open.length - located.length;
    let note = $('#bigMap .map-note');
    const filtered = status !== 'active' || range.key !== 'all';
    const msg = !counts.all ? (filtered && data.reports.length ? 'No incidents match your filters. <button class="btn btn--sm btn--fit" id="mClear" type="button">Clear filters</button>' : 'No reports or evacuation centers with a location yet.') : noGps ? `${noGps} open report${noGps > 1 ? 's have' : ' has'} no GPS location – see the Reports page.` : '';
    if (msg) { if (!note) { note = document.createElement('div'); note.className = 'map-note'; $('#bigMap').appendChild(note); } note.innerHTML = msg; } else if (note) note.remove();
    $('#mapStamp').textContent = 'Updated ' + new Date().toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
  }

  async function load() {
    const [reports, centers, settings, blocks] = await Promise.all([api('/admin/reports'), api('/centers'), api('/admin/settings'), api('/admin/blockages')]);
    data = { reports, centers, blocks, settings }; lastOk = new Date(); $('#mapOffline').hidden = true;
    if (!map) map = makeMap($('#bigMap'), settings.mapCenter, 15);
    draw();
    if (selected) { const r = reports.find((x) => x.id === selected); if (r) showPanel(r); }
  }
  $$('#mapChips .chip').forEach((c) => c.addEventListener('click', () => {
    $$('#mapChips .chip').forEach((x) => x.classList.toggle('is-on', x === c));
    filter = c.dataset.f; draw();
  }));
  const clock = (d) => d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
  const offline = () => { $('#mapOfflineText').textContent = `Live updates paused · last updated ${lastOk ? clock(lastOk) : 'never'}. Reconnecting…`; $('#mapOffline').hidden = false; };
  $('#mapRetry').addEventListener('click', () => load().catch(offline));
  $('#mStatus').addEventListener('change', (e) => { status = e.target.value; draw(); });
  const RLAB = { all: 'All time', hour: 'Last hour', day: 'Last 24 hours', week: 'Last 7 days' };
  $('#mRange').addEventListener('click', async () => {
    const iso = (t) => new Date(t).toLocaleDateString('en-CA');
    const out = await EH.modal({
      title: 'Date range', submit: 'Apply range',
      fields: [
        { name: 'key', label: 'Show reports from', type: 'select', value: range.key, options: [{ value: 'all', label: 'All time' }, { value: 'hour', label: 'Last hour' }, { value: 'day', label: 'Last 24 hours' }, { value: 'week', label: 'Last 7 days' }, { value: 'custom', label: 'Custom dates' }], full: true },
        { name: 'from', label: 'From (custom)', type: 'date', value: range.from ? iso(range.from) : '' },
        { name: 'to', label: 'To (custom)', type: 'date', value: range.to ? iso(range.to) : '' },
      ],
      onSubmit: (v) => { if (v.key === 'custom' && (!v.from || !v.to || v.from > v.to)) throw new Error('Choose a start date and an end date after it.'); return v; },
    });
    if (!out) return;
    range = out.key === 'custom' ? { key: 'custom', from: new Date(out.from + 'T00:00:00').getTime(), to: new Date(out.to + 'T23:59:59').getTime() } : { key: out.key, from: null, to: null };
    $('#mRange').textContent = out.key === 'custom' ? `${out.from} – ${out.to}` : RLAB[out.key]; draw();
  });
  $('#mLayers').addEventListener('click', (e) => { e.stopPropagation(); $('#layersPanel').hidden = !$('#layersPanel').hidden; });
  document.addEventListener('click', (e) => { if (!$('#layersPanel').contains(e.target)) $('#layersPanel').hidden = true; });
  $$('#layersPanel [data-layer]').forEach((c) => c.addEventListener('change', () => { layers[c.dataset.layer] = c.checked; draw(); }));
  document.addEventListener('click', (e) => { if (e.target.id === 'mClear') { status = 'active'; range = { key: 'all', from: null, to: null }; $('#mStatus').value = 'active'; $('#mRange').textContent = 'All time'; draw(); } });
  try { await load(); } catch (e) { fail(e); offline(); }
  setInterval(() => load().catch(offline), 30000);
})();
