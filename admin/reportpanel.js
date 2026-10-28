'use strict';
/* Report detail panel shared by Reports and Incident Map. */
const RP = (() => {
  const { esc, api, ago, when, toast, fail, confirmBox, modal } = EH;
  let teams = [], targets = [], loaded = false;
  async function load() {
    if (loaded) return; loaded = true;
    try { const st = await api('/admin/settings'); teams = st.teams || []; targets = (st.escalation && st.escalation.targets) || []; } catch { /* panel still works with free text */ }
  }
  const SC = { NEW: 'blue', VERIFIED: 'green', DISPATCHED: 'red', RESOLVED: 'gray', REJECTED: 'gray' };
  const UC = { Low: 'gray', Medium: 'blue', High: 'amber', Critical: 'red' };
  const ico = (n) => `<svg class="icon"><use href="#${n}"/></svg>`;
  const REJECT_REASONS = ['Duplicate report', 'Not an emergency', 'Not enough information', 'False or test report', 'Outside the barangay'];
  const OUTCOMES = ['Resolved on site', 'Referred to another office', 'False alarm / nothing found', 'Handled by the resident'];
  const TEMPLATES = [
    ['Ask for photo and exact location', 'Please send a photo and the exact location (street, landmark or purok) so responders can find it.'],
    ['Ask how many people are affected', 'How many people are affected or in danger? Is anyone hurt?'],
    ['Ask if it is still happening', 'Is the problem still happening right now? Please reply with an update.'],
    ['Write my own message', ''],
  ];
  const ACTIONS = {
    NEW: [['VERIFIED', 'Verify and notify nearby residents', 'btn--primary', 'i-check'], ['@info', 'Request more info', '', ''], ['REJECTED', 'Reject', 'btn--danger', 'i-x']],
    VERIFIED: [['DISPATCHED', 'Dispatch responders', 'btn--primary', 'i-users'], ['@info', 'Request more info', '', ''], ['RESOLVED', 'Mark resolved', '', 'i-check'], ['@escalate', 'Escalate', '', ''], ['REJECTED', 'Reject', 'btn--danger', 'i-x']],
    DISPATCHED: [['@onsite', 'Mark on site', 'btn--primary', 'i-check'], ['RESOLVED', 'Mark resolved', '', 'i-check'], ['@escalate', 'Escalate', '', '']],
    RESOLVED: [['NEW', 'Reopen', '', '']],
    REJECTED: [['NEW', 'Reopen', '', '']],
  };
  const where = (r) => r.locationText || (r.lat != null ? `${r.lat.toFixed(5)}, ${r.lng.toFixed(5)}` : '—');

  function progress(r) {
    if (!['VERIFIED', 'DISPATCHED', 'RESOLVED'].includes(r.status)) return '';
    const stamp = (txt) => { const t = (r.timeline || []).find((x) => x.text.startsWith(txt)); return t ? t.at : null; };
    const steps = [['Verified', stamp('Verified')], ['Dispatched', stamp('Responders dispatched')], ['On site', r.onSiteAt || null], ['Resolved', stamp('Marked resolved')]];
    return `<p class="eyebrow">Progress</p><ol class="steps">${steps.map(([n, at]) => `<li class="${at ? 'is-done' : ''}"><i></i><b>${n}</b><span>${at ? esc(ago(at)) : ''}</span></li>`).join('')}</ol>`;
  }
  function render(r) {
    const acts = (ACTIONS[r.status] || []).map(([s, label, cls, ic]) =>
      `<button class="btn ${cls}" data-act="${s}">${ic ? ico(ic) : ''}${label}</button>`).join('');
    return `
      <div class="panel__head"><span>Report #${esc(r.id)}</span><span class="pill pill--${SC[r.status]} pill--sm pill--caps">${esc(r.status)}</span></div>
      <h2 class="panel__title">${esc(r.type)}</h2>
      <div class="panel__pills"><span class="pill pill--${UC[r.urgency]} pill--sm pill--caps">${esc(r.urgency)} urgency</span>
        <span class="pill pill--gray pill--sm pill--caps">${r.kind === 'incident' ? 'Incident' : 'Hazard'}</span></div>
      <p class="panel__text">${esc(r.description)}</p>
      ${(r.photos || []).length ? `<div class="photos" data-photos="${esc(r.photos.join(','))}"><span class="photos__label">Photos (${r.photos.length})</span></div>` : ''}
      <dl class="kv">
        <div class="kv__row"><dt>Location</dt><dd>${esc(r.locationText || '—')}</dd></div>
        <div class="kv__row"><dt>GPS</dt><dd>${r.lat != null ? `${r.lat.toFixed(5)}, ${r.lng.toFixed(5)}` : 'Not provided'}${r.outside ? ' <b style="color:var(--danger)">· Outside the barangay area</b>' : ''}</dd></div>
        ${r.reportedAt && Math.abs(new Date(r.createdAt) - new Date(r.reportedAt)) > 60000
          ? `<div class="kv__row"><dt>Filed on phone</dt><dd>${esc(when(r.reportedAt))} (offline)</dd></div>
        <div class="kv__row"><dt>Received</dt><dd>${esc(when(r.createdAt))} (${esc(ago(r.createdAt))})</dd></div>`
          : `<div class="kv__row"><dt>Reported</dt><dd>${esc(when(r.createdAt))} (${esc(ago(r.createdAt))})</dd></div>`}
        <div class="kv__row"><dt>Reporter</dt><dd>${esc(r.reporterName)}${r.anonymous ? ' · name hidden publicly' : ''}</dd></div>
      </dl>
      ${progress(r)}
      <p class="eyebrow">Assign to</p>
      <div class="inline-add">${teams.length
        ? `<select class="input" data-assign style="flex:1;width:auto"><option value="">Choose responder team</option>${[...new Set([...teams.map((t) => t.name), ...(r.assignedTo ? [r.assignedTo] : [])])].map((n) => `<option${n === r.assignedTo ? ' selected' : ''}>${esc(n)}</option>`).join('')}</select>`
        : `<input class="input" data-assign value="${esc(r.assignedTo)}" placeholder="e.g. Fire team, BDRRM (add teams in Database → Responders)" maxlength="60" style="flex:1;width:auto">`}<button class="btn btn--fit" data-save-assign style="height:40px">Save</button></div>
      <p class="eyebrow">Timeline</p>
      <div class="timeline">${r.timeline.map((t) => `<div class="timeline__item"><i class="dot dot--sm dot--gray"></i>${esc(t.text)}<time>${esc(ago(t.at))}</time></div>`).join('')}</div>
      <div class="panel__actions">${acts}<button class="btn" data-call>${ico('i-phone')}Call reporter</button></div>`;
  }

  function bind(panel, r, onChange) {
    const ph = panel.querySelector('[data-photos]');
    if (ph) ph.dataset.photos.split(',').forEach(async (name) => {
      try {
        const res = await fetch('/api/photos/' + encodeURIComponent(name), { headers: { Authorization: 'Bearer ' + localStorage.getItem(EH.TOKEN) } });
        if (!res.ok) return;
        const url = URL.createObjectURL(await res.blob());
        const a = document.createElement('a'); a.href = url; a.target = '_blank'; a.rel = 'noopener'; a.className = 'photos__item';
        const img = document.createElement('img'); img.src = url; img.alt = 'Photo attached to report ' + r.id; a.appendChild(img); ph.appendChild(a);
      } catch { /* photo just doesn't show */ }
    });
    const patch = async (body, okMsg) => {
      try { const upd = await api('/admin/reports/' + encodeURIComponent(r.id), { method: 'PATCH', body }); toast(okMsg, 'ok'); onChange(upd); }
      catch (e) { fail(e); }
    };
    const opts = (arr) => arr.map((x) => (typeof x === 'string' ? x : { value: x[0], label: x[0] }));
    panel.querySelectorAll('[data-act]').forEach((b) => b.addEventListener('click', async () => {
      const s = b.dataset.act;
      if (s === '@onsite') return patch({ onSite: true }, 'Marked on site');
      if (s === '@info') {
        const out = await modal({
          title: 'Ask the reporter for details', sub: `Sent to the reporter of #${r.id} as an in-app notification.`, submit: 'Send request',
          fields: [
            { name: 'template', label: 'Template', type: 'select', options: TEMPLATES.map((t) => t[0]), full: true },
            { name: 'message', label: 'Message', type: 'textarea', max: 160, required: true, full: true, placeholder: 'Write your message (keep it short and clear)', value: TEMPLATES[0][1] },
          ],
          onOpen: (bg) => { const sel = bg.querySelector('[name=template]'), ta = bg.querySelector('[name=message]'); sel.addEventListener('change', () => { const t = TEMPLATES.find((x) => x[0] === sel.value); ta.value = t ? t[1] : ''; ta.focus(); }); },
          onSubmit: (v) => api(`/admin/reports/${encodeURIComponent(r.id)}/request-info`, { method: 'POST', body: { message: v.message } }),
        });
        if (out && out !== true) { toast('Request sent to the reporter', 'ok'); onChange(out); }
        return;
      }
      if (s === '@escalate') {
        const has = targets.length > 0;
        const out = await modal({
          title: `Escalate report #${r.id}`, sub: 'Records the escalation on the report. Contact the office by phone or radio as well.', submit: 'Escalate',
          fields: [
            has ? { name: 'to', label: 'Escalate to', type: 'select', options: targets.map((t) => ({ value: t.name, label: t.note ? `${t.name} – ${t.note}` : t.name })), required: true, full: true }
                : { name: 'to', label: 'Escalate to (office or agency)', required: true, full: true, placeholder: 'e.g. City DRRMO' },
            { name: 'reason', label: 'Reason', type: 'textarea', max: 300, required: true, full: true, placeholder: 'Why escalate?' },
          ],
          onSubmit: (v) => api(`/admin/reports/${encodeURIComponent(r.id)}/escalate`, { method: 'POST', body: v }),
        });
        if (out && out !== true) { toast('Escalation recorded', 'ok'); onChange(out); }
        return;
      }
      if (s === 'REJECTED') {
        const out = await modal({
          title: `Reject report #${r.id}?`, sub: 'The reporter will be notified with the reason you choose.', submit: 'Reject report', danger: true,
          fields: [
            { name: 'reason', label: 'Reason', type: 'select', options: [{ value: '', label: 'Select a reason' }, ...opts(REJECT_REASONS)], required: true, full: true },
            { name: 'note', label: 'Note to reporter (optional)', type: 'textarea', max: 300, full: true, placeholder: 'Add a short explanation' },
          ],
          onSubmit: (v) => { if (!v.reason) throw new Error('Select a reason to continue.'); return v; },
        });
        if (out) patch({ status: s, reason: out.reason, note: out.note }, `${r.id} → rejected`);
        return;
      }
      if (s === 'RESOLVED') {
        const out = await modal({
          title: `Mark #${r.id} as resolved?`, sub: 'Record the outcome so the report history stays accurate.', submit: 'Mark resolved',
          fields: [
            { name: 'outcome', label: 'Outcome', type: 'select', options: OUTCOMES, full: true },
            { name: 'note', label: 'Resolution note', type: 'textarea', max: 300, required: true, full: true, placeholder: 'What was done?' },
            { name: 'notifyReporter', label: 'Notify the reporter', type: 'checkbox', value: true, full: true },
          ],
        });
        if (out) patch({ status: s, outcome: out.outcome, note: out.note, notifyReporter: out.notifyReporter }, `${r.id} → resolved`);
        return;
      }
      if (s === 'DISPATCHED') {
        const out = await modal({
          title: `Dispatch responders to #${r.id}`, sub: 'Choose who goes. The reporter is told help is on the way.', submit: 'Dispatch',
          fields: [
            teams.length ? { name: 'team', label: 'Responder team', type: 'select', options: [{ value: '', label: 'Choose responder team' }, ...teams.map((t) => ({ value: t.name, label: t.note ? `${t.name} – ${t.note}` : t.name }))], full: true }
                         : { name: 'team', label: 'Responder team', full: true, placeholder: 'e.g. Fire team, BDRRM', value: r.assignedTo },
            { name: 'instructions', label: 'Instructions (optional)', type: 'textarea', max: 300, full: true, placeholder: 'What should the team know?' },
          ],
        });
        if (out) patch({ status: s, team: out.team, instructions: out.instructions }, `${r.id} → dispatched`);
        return;
      }
      patch({ status: s }, `${r.id} → ${s.toLowerCase()}`);
    }));
    panel.querySelector('[data-save-assign]').addEventListener('click', () => patch({ assignedTo: panel.querySelector('[data-assign]').value }, 'Assignment saved'));
    panel.querySelector('[data-call]').addEventListener('click', () => {
      let shown = '';
      const dd = modal({
        title: 'Call reporter', sub: 'The number is masked. Revealing it is recorded in the audit log.', submit: 'Close',
        fields: [],
        onOpen: (bg, form) => {
          form.querySelector('.modal__actions').insertAdjacentHTML('beforebegin', `<div class="callbox"><p class="callbox__num" data-num>${esc(r.reporterContactMasked || '—')}</p>
            <p class="callbox__who">${r.anonymous ? 'Public report · name hidden' : esc(r.reporterName)}</p>
            <div class="callbox__row"><button type="button" class="btn btn--sm btn--fit" data-reveal>Reveal</button><button type="button" class="btn btn--sm btn--fit" data-copy hidden>Copy number</button><a class="btn btn--sm btn--primary btn--fit" data-dial hidden>Call now</a></div>
            <p class="callbox__hint">“Call now” opens your phone’s dialer or softphone. The call is made from your device.</p></div>`);
          form.querySelector('[data-reveal]').onclick = async (e) => {
            try {
              const { contact } = await api(`/admin/residents/${encodeURIComponent(r.userId)}/contact`);
              shown = contact; form.querySelector('[data-num]').textContent = contact; e.target.hidden = true;
              form.querySelector('[data-copy]').hidden = false; const d = form.querySelector('[data-dial]'); d.hidden = false; d.href = 'tel:' + contact;
            } catch (err) { fail(err); }
          };
          form.querySelector('[data-copy]').onclick = async () => { try { await navigator.clipboard.writeText(shown); toast('Number copied', 'ok'); } catch { toast(shown); } };
        },
      });
      return dd;
    });
  }
  return { render, bind, where, SC, UC, load };
})();
