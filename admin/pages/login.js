'use strict';
(() => {
  const { $ } = EH;
  if (localStorage.getItem(EH.TOKEN) && EH.api) {
    // already signed in? go straight to the dashboard
    try { const u = JSON.parse(localStorage.getItem(EH.USER)); if (u && u.role === 'admin') location.href = 'index.html'; } catch { /* stay */ }
  }
  $('#loginForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    const err = $('#err'), btn = $('#go');
    err.hidden = true;
    const contact = $('#u').value.trim(), password = $('#p').value;
    if (!contact || !password) { err.textContent = 'Enter your username and password'; err.hidden = false; return; }
    btn.disabled = true;
    try {
      const out = await EH.api('/auth/login', { method: 'POST', body: { contact, password }, auth: false });
      if (out.user.role !== 'admin') throw new Error('This account is not an administrator.');
      localStorage.setItem(EH.TOKEN, out.token);
      localStorage.setItem(EH.USER, JSON.stringify(out.user));
      location.href = 'index.html';
    } catch (ex) { err.textContent = ex.message; err.hidden = false; btn.disabled = false; }
  });
})();
