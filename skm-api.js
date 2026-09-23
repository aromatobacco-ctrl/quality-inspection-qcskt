(function () {
  'use strict';

  const SESSION_KEY = 'qc_skm_session_token';
  let client = null;

  function getClient() {
    if (client) return client;
    const config = window.SKM_SUPABASE_CONFIG || {};
    if (!config.url || !config.publishableKey || /YOUR|PASTE/i.test(`${config.url} ${config.publishableKey}`)) {
      throw new Error('Supabase belum dikonfigurasi. Isi URL dan publishable key pada supabase-config.js.');
    }
    if (!window.supabase || typeof window.supabase.createClient !== 'function') {
      throw new Error('Library Supabase gagal dimuat. Periksa koneksi internet lalu muat ulang halaman.');
    }
    client = window.supabase.createClient(config.url, config.publishableKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }
    });
    return client;
  }

  function parseBody(body) {
    if (!body) return {};
    if (typeof body === 'string') {
      try { return JSON.parse(body); } catch { return {}; }
    }
    return body;
  }

  function friendlyError(error) {
    const message = error && error.message ? error.message : String(error || 'Permintaan gagal.');
    if (message.includes('Failed to fetch')) return 'Tidak dapat terhubung ke Supabase. Periksa internet dan konfigurasi project.';
    if (message.includes('skm_api_request')) return 'Database SKM belum siap. Jalankan supabase-setup.sql di SQL Editor Supabase.';
    return message;
  }

  async function skmApiRequest(path, options = {}) {
    const method = String(options.method || 'GET').toUpperCase();
    const payload = parseBody(options.body);
    const sessionToken = localStorage.getItem(SESSION_KEY);
    const { data, error } = await getClient().rpc('skm_api_request', {
      p_path: path,
      p_method: method,
      p_payload: payload,
      p_session_token: sessionToken
    });

    if (error) throw new Error(friendlyError(error));
    const result = data || {};
    if (result.sessionToken) {
      localStorage.setItem(SESSION_KEY, result.sessionToken);
      delete result.sessionToken;
    }
    if (result.clearSession) {
      localStorage.removeItem(SESSION_KEY);
      delete result.clearSession;
    }
    if (result.__error) {
      if (Number(result.__status) === 401) localStorage.removeItem(SESSION_KEY);
      const requestError = new Error(result.__error);
      requestError.status = Number(result.__status || 400);
      throw requestError;
    }
    return result;
  }

  window.skmApiRequest = skmApiRequest;
  window.skmClearSession = () => localStorage.removeItem(SESSION_KEY);
})();
