'use strict';
(async () => {
  if (!EH.init()) return;
  const { $, esc, api, ago, when, toast, fail, modal, confirmBox, makeMap, marker } = EH;
  const REASONS = ['Flood', 'Accident', 'Road works', 'Fallen tree', 'Fire', 'Event / parade', 'Other'];
  let map = null, layer = null, pin = null, items = [], picked = null;

  $('#bkReason').innerHTML = REASONS.map((r) => `<option>${esc(r)}</option>`).join('');

  // datetime-local gives local time without a zone; turn it into a real instant for the server, and back.
  const toIso = (v) => (v ? new Date(v).toISOString() : '');
  const toLocalInput = (iso) => { if (!iso) return ''; const d = new Date(iso); d.setMinutes(d.getMinutes() - d.getTimezoneOffset()); return d.toISOString().slice(0, 16); };

  function setPick(lat, lng) {
    picked = { lat, lng };
    $('#bkLoc').textContent = `${lat.toFixed(5)}, ${lng.toFixed(5)}`; $('#bkLoc').classList.add('is-set');
    if (pin) pin.remove();
    pin = L.marker([lat, lng], { draggable: true }).addTo(map);
    pin.on('dragend', () => { const p = pin.getLatLng(); setPick(p.lat, p.lng); });
  }

  function draw() {
    if (!map) return;
    if (layer) layer.remove();
    layer = L.featureGroup().addTo(map);
    items.filter((x) => x.lat != null).forEach((x) => {
      marker(layer, x.lat, x.lng, 'block', { radius: 11 }).bindTooltip(`${x.title} · ${x.reason}${x.expired ? ' (time passed)' : ''}`).on('click', () => focusItem(x.id));
    });
    $('#bkCount').textContent = items.length;
    $('#bkItems').innerHTML = items.length ? items.map((x) => `<div class="bk__item" data-id="${esc(x.id)}">
      <div><span class="bk__tag${x.expired ? ' bk__tag--exp' : ''}">${x.expired ? 'TIME PASSED' : esc(x.reason.toUpperCase())}</span><b>${esc(x.title)}</b></div>
      <small>${x.expired ? esc(x.reason) + ' · ' : ''}${esc(x.details || '')}${x.details ? '<br>' : ''}Marked ${esc(ago(x.createdAt))}${x.createdBy ? ' by ' + esc(x.createdBy) : ''}${x.until ? ' · expected to reopen ' + esc(when(x.until)) : ' · no end time set'}</small>
      <div class="row"><button class="btn btn--sm" data-act="show">Show on map</button><button class="btn btn--sm" data-act="edit">Edit</button>
      <button class="btn btn--primary btn--sm" data-act="clear">Road is open again</button></div></div>`).join('')
      : '<div class="empty"><b>No blocked roads</b>Roads you mark as blocked appear here. Residents see them on their map.</div>';
  }
  function focusItem(id) {
    const x = items.find((y) => y.id === id); if (!x || !map) return;
    map.setView([x.lat, x.lng], Math.max(map.getZoom(), 17));
    const el = document.querySelector(`.bk__item[data-id="${CSS.escape(id)}"]`); if (el) el.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  }
  async function load() { items = await api('/admin/blockages'); draw(); }

  $('#bkItems').addEventListener('click', async (e) => {
    const b = e.target.closest('[data-act]'); const card = e.target.closest('.bk__item'); if (!b || !card) return;
    const x = items.find((y) => y.id === card.dataset.id); if (!x) return;
    try {
      if (b.dataset.act === 'show') focusItem(x.id);
      else if (b.dataset.act === 'clear') {
        if (!(await confirmBox('Road is open again?', `“${x.title}” will be removed from the map for residents.`, 'Remove blockage', false))) return;
        await api('/admin/blockages/' + encodeURIComponent(x.id), { method: 'DELETE' }); toast('Blockage removed', 'ok'); await load();
      } else if (b.dataset.act === 'edit') {
        const out = await modal({ title: 'Edit blockage', submit: 'Save', fields: [
          { name: 'title', label: 'Road / place', value: x.title, required: true, max: 120, full: true },
          { name: 'reason', label: 'Reason', type: 'select', options: REASONS, value: x.reason },
          { name: 'until', label: 'Expected to reopen', type: 'datetime-local', value: toLocalInput(x.until) },
          { name: 'details', label: 'Details', value: x.details, max: 300, full: true }],
          onSubmit: (v) => api('/admin/blockages/' + encodeURIComponent(x.id), { method: 'PATCH', body: { ...v, until: toIso(v.until) } }) });
        if (out) { toast('Blockage updated', 'ok'); await load(); }
      }
    } catch (err) { fail(err); }
  });

  $('#bkForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    const err = $('#bkErr'); err.hidden = true;
    const title = $('#bkTitle').value.trim();
    if (title.length < 3) { err.textContent = 'Name the road or place that is blocked'; err.hidden = false; return; }
    if (!picked) { err.textContent = 'Click the map to pick the blocked spot'; err.hidden = false; return; }
    const btn = $('#bkAdd'); btn.disabled = true;
    try {
      await api('/admin/blockages', { method: 'POST', body: { title, reason: $('#bkReason').value, details: $('#bkDetails').value.trim(), until: toIso($('#bkUntil').value), lat: picked.lat, lng: picked.lng, notify: $('#bkNotify').checked } });
      toast('Road marked as blocked', 'ok');
      $('#bkForm').reset(); $('#bkNotify').checked = true; picked = null; $('#bkLoc').textContent = 'Not picked yet. Click the map.'; $('#bkLoc').classList.remove('is-set');
      if (pin) { pin.remove(); pin = null; }
      await load();
    } catch (x) { err.textContent = x.message; err.hidden = false; } finally { btn.disabled = false; }
  });

  try {
    const settings = await api('/admin/settings');
    map = makeMap($('#bkMap'), settings.mapCenter, 16);
    if (map) map.on('click', (ev) => setPick(ev.latlng.lat, ev.latlng.lng));
    await load();
    if (items.length && map) map.fitBounds(items.map((x) => [x.lat, x.lng]), { padding: [60, 60], maxZoom: 17 });
  } catch (e) { fail(e); }
})();
