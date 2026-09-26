/* Koneksi aktif pada dashboard. Satu pengguna dapat membuka beberapa tab. */
(() => {
  let client, channel, userId, onChange;
  let online = new Set();
  const label = () => document.getElementById('myPresence');

  function update() {
    if (!channel) return;
    const state = channel.presenceState();
    online = new Set(Object.values(state).flat().map(item => String(item.userId || '')));
    if (label()) {
      const connected = online.has(userId);
      label().textContent = connected ? '● Online' : '○ Offline';
      label().className = 'px-2 ' + (connected ? 'text-emerald-300' : 'text-amber-300');
    }
    if (onChange) onChange();
  }

  async function stop() {
    if (channel) {
      const old = channel;
      channel = null;
      try { await old.untrack(); await client.removeChannel(old); } catch (_) {}
    }
    online.clear();
  }

  function start(user, adminUpdate) {
    if (!user || !user.id || !window.supabase) return;
    userId = String(user.id);
    onChange = adminUpdate;
    const config = window.QC_SUPABASE_CONFIG || {};
    if (!config.url || !config.publishableKey) return;
    client = window.supabase.createClient(config.url, config.publishableKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }
    });
    channel = client.channel('qc-skt-dashboard-presence', {
      config: { presence: { key: userId + ':' + crypto.randomUUID() } }
    });
    channel.on('presence', { event: 'sync' }, update)
      .on('presence', { event: 'join' }, update)
      .on('presence', { event: 'leave' }, update)
      .subscribe(async status => {
        if (status === 'SUBSCRIBED' && channel) {
          await channel.track({ userId });
        } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
          online.clear();
          if (label()) label().textContent = '○ Koneksi terputus';
          if (onChange) onChange();
        }
      });
    window.addEventListener('pagehide', () => { if (channel) channel.untrack(); }, { once: true });
  }

  window.qcPresence = { start, stop, isOnline: id => online.has(String(id)) };
})();
