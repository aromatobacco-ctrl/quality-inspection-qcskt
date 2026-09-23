-- Quality Inspection SKT / SKM
-- Izinkan satu akun login pada dua perangkat atau lebih secara bersamaan.
-- Cara pakai: Supabase > SQL Editor > New query > tempel seluruh isi > Run.
-- Patch ini hanya memperbarui perilaku login pada fungsi yang sudah terpasang.
-- Sesi perangkat lain, data inspeksi, akun, password, dan hak akses tetap ada.
-- Logout tetap berlaku hanya untuk token perangkat yang melakukan logout.
-- Referensi: https://www.postgresql.org/docs/current/functions-info.html
--            https://www.postgresql.org/docs/current/sql-createfunction.html

begin;

do $qc_multi_device_patch$
declare
  v_function regprocedure;
  v_definition text;
  v_updated text;
  v_matches integer;
  v_login_start integer;
  v_login_tail text;
  v_pattern constant text := $pattern$delete[[:space:]]+from[[:space:]]+public[.]app_sessions[[:space:]]+where[[:space:]]+user_id[[:space:]]*=[[:space:]]*v_user[.]id[[:space:]]*;$pattern$;
  v_replacement constant text := $replacement$-- QC_MULTI_DEVICE_LOGIN_V1
    -- Login baru mempertahankan sesi pada perangkat lain.
    -- Token lama browser yang sedang login ulang boleh diganti.
    if p_session_token is not null and p_session_token <> '' then
      delete from public.app_sessions
      where user_id = v_user.id
        and token_hash = encode(extensions.digest(p_session_token, 'sha256'), 'hex');
    end if;$replacement$;
begin
  v_function := pg_catalog.to_regprocedure('public.qc_api_request(text,text,jsonb,text)');
  if v_function is null then
    raise exception 'Fungsi qc_api_request belum ditemukan. Gunakan project Supabase yang terhubung ke dashboard ini.';
  end if;

  v_definition := pg_catalog.pg_get_functiondef(v_function);
  if strpos(v_definition, 'QC_MULTI_DEVICE_LOGIN_V1') > 0 then
    raise notice 'Login beberapa perangkat sudah aktif; tidak perlu perubahan lagi.';
    return;
  end if;

  select count(*) into v_matches
  from regexp_matches(v_definition, v_pattern, 'gi');
  v_login_start := strpos(lower(v_definition), 'if p_path = ''/api/auth/login''');
  if v_login_start = 0 then
    raise exception 'Blok login tidak sesuai versi yang diperiksa. Tidak ada perubahan yang diterapkan.';
  end if;
  v_login_tail := substring(v_definition from v_login_start);
  if v_matches <> 1 or v_login_tail !~* v_pattern then
    raise exception 'Aturan sesi login berbeda dari file yang diperiksa. Tidak ada perubahan yang diterapkan; gunakan file fungsi terbaru.';
  end if;

  v_updated := regexp_replace(v_definition, v_pattern, v_replacement, 'i');
  if v_updated = v_definition then
    raise exception 'Patch login tidak mengubah fungsi. Tidak ada perubahan yang diterapkan.';
  end if;

  -- CREATE OR REPLACE mempertahankan fungsi saat ini, termasuk endpoint lain.
  execute v_updated;
  raise notice 'Login beberapa perangkat aktif. Setiap perangkat menerima token sesi tersendiri.';
end;
$qc_multi_device_patch$;

select 'Aktif: satu akun dapat login di dua perangkat atau lebih; logout hanya di perangkat saat ini.' as hasil;

commit;
