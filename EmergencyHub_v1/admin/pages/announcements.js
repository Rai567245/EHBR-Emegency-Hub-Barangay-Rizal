'use strict';
(async () => {
  if (!EH.init()) return;
  const { $, esc, api, ago, fail, toast, confirmBox } = EH;
  const PILL = { alert: 'red', advisory: 'blue', event: 'gray' };

  async function load() {
    const list = await api('/announcements');
    $('#anList').innerHTML = list.length ? list.map((a) => `
      <article class="an__item"><div class="an__head"><span class="pill pill--${PILL[a.category]} pill--sm pill--caps">${esc(a.category)}</span><b>${esc(a.title)}</b>
        <time>${esc(ago(a.createdAt))}</time><button class="btn btn--danger btn--sm" data-del="${esc(a.id)}" style="height:28px;padding:0 10px">Delete</button></div>
        <p>${esc(a.body)}</p></article>`).join('')
      : '<div class="card"><div class="empty"><b>No announcements yet</b>Write one on the left – residents see it in the app’s News tab right away.</div></div>';
  }
  $('#anList').addEventListener('click', async (e) => {
    const b = e.target.closest('[data-del]'); if (!b) return;
    if (!(await confirmBox('Delete this announcement?', 'Residents will no longer see it in the app.', 'Delete'))) return;
    try { await api('/admin/announcements/' + encodeURIComponent(b.dataset.del), { method: 'DELETE' }); toast('Announcement deleted', 'ok'); load(); } catch (x) { fail(x); }
  });
  $('#anForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    const err = $('#anErr'); err.hidden = true;
    const body = { category: $('#anCat').value, title: $('#anTitle').value.trim(), body: $('#anBody').value.trim(), push: $('#anPush').checked };
    if (!body.title || !body.body) { err.textContent = 'Title and message are required'; err.hidden = false; return; }
    try { await api('/admin/announcements', { method: 'POST', body }); $('#anTitle').value = ''; $('#anBody').value = ''; toast('Announcement sent', 'ok'); load(); }
    catch (x) { err.textContent = x.message; err.hidden = false; }
  });
  async function pushStatus() {
    try {
      const s = await api('/admin/push-status');
      const box = $('#anPush'), el = $('#pushStatus');
      if (s.enabled) {
        el.textContent = `Push is on · ${s.devices} phone${s.devices === 1 ? '' : 's'} registered. Residents also see every announcement under the bell icon in the app.`;
      } else {
        box.checked = false; box.disabled = true;
        el.textContent = 'Push is not set up yet, so phones will not buzz. Residents still see this under the bell icon in the app. To switch push on, follow “Push notifications” in the README.';
      }
    } catch (e) { fail(e); }
  }
  try { await Promise.all([load(), pushStatus()]); } catch (e) { fail(e); }
})();
