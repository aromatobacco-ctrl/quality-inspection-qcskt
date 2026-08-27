-- ================================================================
-- QUALITY INSPECTION SKT - GITHUB PAGES + SUPABASE (TANPA RENDER)
-- Jalankan SELURUH file ini satu kali di Supabase > SQL Editor.
-- File ini aman dijalankan setelah db/schema.sql dari paket sebelumnya.
-- ================================================================

create extension if not exists pgcrypto with schema extensions;

-- Kolom pengamanan login tambahan.
alter table public.app_users
  add column if not exists failed_login_count integer not null default 0,
  add column if not exists locked_until timestamptz;

-- Sesi disimpan sebagai hash. Token mentah hanya berada di browser pengguna.
create table if not exists public.app_sessions (
  token_hash text primary key,
  user_id uuid not null references public.app_users(id) on delete cascade,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index if not exists app_sessions_user_idx on public.app_sessions(user_id);
create index if not exists app_sessions_expiry_idx on public.app_sessions(expires_at);
create unique index if not exists app_users_username_lower_unique
  on public.app_users (lower(username));
create unique index if not exists brands_code_lower_unique
  on public.brands (lower(code));
create unique index if not exists groups_master_name_lower_unique
  on public.groups_master (lower(name));
create unique index if not exists sampling_times_number_unique
  on public.sampling_times (sampling_no);

-- Data awal tetap tersedia jika schema lama belum melakukan seed.
insert into public.app_settings (id, target_green, target_yellow, default_sample_size)
values (1, 95, 90, 10)
on conflict (id) do nothing;

insert into public.backup_status (id, month, completed_at, completed_by)
values (1, null, null, null)
on conflict (id) do nothing;

insert into public.sampling_times (sampling_no, time_label, is_active)
values (1, '08:00', true), (2, '10:00', true), (3, '13:00', true)
on conflict (sampling_no) do nothing;

insert into public.brands (code, is_active)
values
  ('ARO', true), ('ARI 12', true), ('ARI 16', true), ('ARS', true),
  ('AST', true), ('ASM', true), ('ASC', true), ('ASB', true),
  ('ASA', true), ('ARA', true)
on conflict do nothing;

insert into public.groups_master (name, is_active)
select 'Kelompok ' || lpad(g::text, 2, '0'), true
from generate_series(1, 24) as g
on conflict do nothing;

-- Semua operasi dashboard masuk melalui satu RPC terkontrol.
create or replace function public.qc_api_request(
  p_path text,
  p_method text default 'GET',
  p_payload jsonb default '{}'::jsonb,
  p_session_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user public.app_users%rowtype;
  v_target public.app_users%rowtype;
  v_inspection public.inspections%rowtype;
  v_moisture public.moisture_records%rowtype;
  v_pack public.pack_records%rowtype;
  v_method text := upper(coalesce(p_method, 'GET'));
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_result jsonb;
  v_token text;
  v_token_hash text;
  v_id uuid;
  v_group_id uuid;
  v_group_name text;
  v_sampling integer;
  v_sample_size integer;
  v_failed integer;
  v_item jsonb;
begin
  -- Bersihkan sesi kedaluwarsa secara ringan pada setiap permintaan.
  delete from public.app_sessions where expires_at <= now();

  -- -------------------- AUTH: STATUS --------------------
  if p_path = '/api/auth/status' and v_method = 'GET' then
    if p_session_token is null or p_session_token = '' then
      return jsonb_build_object('user', null);
    end if;

    select u.* into v_user
    from public.app_sessions s
    join public.app_users u on u.id = s.user_id
    where s.token_hash = encode(extensions.digest(p_session_token, 'sha256'), 'hex')
      and s.expires_at > now()
      and u.is_active = true;

    if not found then
      return jsonb_build_object('user', null, 'clearSession', true);
    end if;

    return jsonb_build_object(
      'user', jsonb_build_object(
        'id', v_user.id,
        'displayName', v_user.display_name,
        'username', v_user.username,
        'role', v_user.role,
        'isActive', v_user.is_active
      )
    );
  end if;

  -- -------------------- AUTH: ADMIN PERTAMA --------------------
  if p_path = '/api/auth/bootstrap' and v_method = 'POST' then
    if exists (select 1 from public.app_users) then
      return jsonb_build_object('__error', 'Admin pertama sudah dibuat. Silakan login.', '__status', 409);
    end if;
    if length(trim(coalesce(v_payload->>'displayName', ''))) < 2 then
      return jsonb_build_object('__error', 'Nama Admin wajib diisi.', '__status', 400);
    end if;
    if trim(coalesce(v_payload->>'username', '')) !~ '^[A-Za-z0-9._-]{3,40}$' then
      return jsonb_build_object('__error', 'Username harus 3–40 karakter dan hanya berisi huruf, angka, titik, garis bawah, atau strip.', '__status', 400);
    end if;
    if length(coalesce(v_payload->>'password', '')) < 8 then
      return jsonb_build_object('__error', 'Password minimal 8 karakter.', '__status', 400);
    end if;

    insert into public.app_users (display_name, username, password_hash, role, is_active)
    values (
      trim(v_payload->>'displayName'),
      lower(trim(v_payload->>'username')),
      extensions.crypt(v_payload->>'password', extensions.gen_salt('bf', 10)),
      'ADMIN',
      true
    )
    returning * into v_user;

    v_token := encode(extensions.gen_random_bytes(32), 'hex');
    v_token_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');
    insert into public.app_sessions (token_hash, user_id, expires_at)
    values (v_token_hash, v_user.id, now() + interval '12 hours');

    return jsonb_build_object(
      'sessionToken', v_token,
      'user', jsonb_build_object(
        'id', v_user.id,
        'displayName', v_user.display_name,
        'username', v_user.username,
        'role', v_user.role,
        'isActive', v_user.is_active
      )
    );
  end if;

  -- -------------------- AUTH: LOGIN --------------------
  if p_path = '/api/auth/login' and v_method = 'POST' then
    select * into v_target
    from public.app_users
    where lower(username) = lower(trim(coalesce(v_payload->>'username', '')))
    limit 1;

    if not found or not v_target.is_active then
      return jsonb_build_object('__error', 'Username atau password salah, atau akun nonaktif.', '__status', 401);
    end if;
    if v_target.locked_until is not null and v_target.locked_until > now() then
      return jsonb_build_object('__error', 'Akun dikunci sementara. Coba lagi 15 menit kemudian.', '__status', 429);
    end if;

    if v_target.password_hash <> extensions.crypt(coalesce(v_payload->>'password', ''), v_target.password_hash) then
      v_failed := coalesce(v_target.failed_login_count, 0) + 1;
      update public.app_users
      set failed_login_count = case when v_failed >= 5 then 0 else v_failed end,
          locked_until = case when v_failed >= 5 then now() + interval '15 minutes' else null end
      where id = v_target.id;
      return jsonb_build_object('__error', 'Username atau password salah, atau akun nonaktif.', '__status', 401);
    end if;

    update public.app_users set failed_login_count = 0, locked_until = null where id = v_target.id
    returning * into v_user;
    delete from public.app_sessions where user_id = v_user.id;
    v_token := encode(extensions.gen_random_bytes(32), 'hex');
    v_token_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');
    insert into public.app_sessions (token_hash, user_id, expires_at)
    values (v_token_hash, v_user.id, now() + interval '12 hours');

    return jsonb_build_object(
      'sessionToken', v_token,
      'user', jsonb_build_object(
        'id', v_user.id,
        'displayName', v_user.display_name,
        'username', v_user.username,
        'role', v_user.role,
        'isActive', v_user.is_active
      )
    );
  end if;

  -- Validasi sesi untuk seluruh endpoint di bawah.
  if p_session_token is not null and p_session_token <> '' then
    select u.* into v_user
    from public.app_sessions s
    join public.app_users u on u.id = s.user_id
    where s.token_hash = encode(extensions.digest(p_session_token, 'sha256'), 'hex')
      and s.expires_at > now()
      and u.is_active = true;
  end if;

  if v_user.id is null then
    return jsonb_build_object('__error', 'Sesi berakhir. Silakan login kembali.', '__status', 401, 'clearSession', true);
  end if;

  -- -------------------- AUTH: LOGOUT --------------------
  if p_path = '/api/auth/logout' and v_method = 'POST' then
    delete from public.app_sessions
    where token_hash = encode(extensions.digest(p_session_token, 'sha256'), 'hex');
    return jsonb_build_object('ok', true, 'clearSession', true);
  end if;

  -- -------------------- MASTER DATA --------------------
  if p_path = '/api/master' and v_method = 'GET' then
    return jsonb_build_object(
      'brands', coalesce((
        select jsonb_agg(jsonb_build_object('id', id, 'code', code, 'isActive', is_active) order by code)
        from public.brands
      ), '[]'::jsonb),
      'groups', coalesce((
        select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'isActive', is_active) order by name)
        from public.groups_master
      ), '[]'::jsonb),
      'samplingTimes', coalesce((
        select jsonb_agg(jsonb_build_object('id', id, 'samplingNo', sampling_no, 'timeLabel', time_label, 'isActive', is_active) order by sampling_no)
        from public.sampling_times
      ), '[]'::jsonb),
      'settings', coalesce((
        select jsonb_build_object('targetGreen', target_green, 'targetYellow', target_yellow, 'defaultSampleSize', default_sample_size)
        from public.app_settings where id = 1
      ), '{}'::jsonb)
    );
  end if;

  if p_path = '/api/master' and v_method = 'PATCH' then
    if v_user.role <> 'ADMIN' then
      return jsonb_build_object('__error', 'Hanya Admin yang dapat mengubah pengaturan.', '__status', 403);
    end if;
    update public.app_settings
    set target_green = coalesce((v_payload->>'targetGreen')::numeric, target_green),
        target_yellow = coalesce((v_payload->>'targetYellow')::numeric, target_yellow),
        default_sample_size = coalesce((v_payload->>'defaultSampleSize')::integer, default_sample_size)
    where id = 1;

    if jsonb_typeof(v_payload->'samplingTimes') = 'array' then
      for v_item in select value from jsonb_array_elements(v_payload->'samplingTimes') loop
        update public.sampling_times
        set time_label = v_item->>'timeLabel'
        where sampling_no = (v_item->>'samplingNo')::integer;
      end loop;
    end if;
    return jsonb_build_object('ok', true);
  end if;

  if p_path = '/api/master/brands' and v_method = 'POST' then
    if v_user.role <> 'ADMIN' then
      return jsonb_build_object('__error', 'Hanya Admin yang dapat menambah brand.', '__status', 403);
    end if;
    if trim(coalesce(v_payload->>'code', '')) = '' then
      return jsonb_build_object('__error', 'Kode brand wajib diisi.', '__status', 400);
    end if;
    begin
      insert into public.brands (code, is_active)
      values (upper(trim(v_payload->>'code')), true);
    exception when unique_violation then
      update public.brands set is_active = true where lower(code) = lower(trim(v_payload->>'code'));
    end;
    return jsonb_build_object('ok', true);
  end if;

  if p_path = '/api/master/brands' and v_method = 'PATCH' then
    if v_user.role <> 'ADMIN' then
      return jsonb_build_object('__error', 'Hanya Admin yang dapat mengubah brand.', '__status', 403);
    end if;
    update public.brands
    set is_active = coalesce((v_payload->>'isActive')::boolean, false)
    where id = (v_payload->>'id')::uuid;
    return jsonb_build_object('ok', true);
  end if;

  -- -------------------- INSPEKSI GILING-BATIL --------------------
  if p_path = '/api/inspections' and v_method = 'GET' then
    select coalesce(jsonb_agg(item order by item->>'date' desc, item->>'kelompok', (item->>'sampling')::integer), '[]'::jsonb)
    into v_result
    from (
      select jsonb_build_object(
        'id', i.id,
        'date', to_char(i.date, 'YYYY-MM-DD'),
        'kelompok', i.kelompok,
        'brand', i.brand,
        'sampling', i.sampling,
        'samplingTime', coalesce(st.time_label, case i.sampling when 1 then '08:00' when 2 then '10:00' else '13:00' end),
        'sampleSize', i.sample_size,
        'params', i.params,
        'inspector', i.inspector,
        'inspectorId', i.inspector_id,
        'createdAt', i.created_at
      ) as item
      from public.inspections i
      left join public.sampling_times st on st.sampling_no = i.sampling
    ) q;
    return jsonb_build_object('inspections', v_result);
  end if;

  if p_path = '/api/inspections' and v_method = 'POST' then
    v_group_id := nullif(v_payload->>'groupId', '')::uuid;
    select name into v_group_name from public.groups_master where id = v_group_id and is_active = true;
    if v_group_name is null then
      return jsonb_build_object('__error', 'Kelompok tidak ditemukan atau tidak aktif.', '__status', 400);
    end if;
    v_sampling := (v_payload->>'sampling')::integer;
    v_sample_size := (v_payload->>'sampleSize')::integer;
    if v_sample_size < 1 or v_sample_size > 100 then
      return jsonb_build_object('__error', 'Jumlah sampel harus antara 1 dan 100.', '__status', 400);
    end if;
    begin
      insert into public.inspections
        (date, group_id, kelompok, brand, sampling, sample_size, params, inspector, inspector_id)
      values
        ((v_payload->>'date')::date, v_group_id, v_group_name, trim(v_payload->>'brand'),
         v_sampling, v_sample_size, coalesce(v_payload->'params', '{}'::jsonb), v_user.display_name, v_user.id)
      returning * into v_inspection;
    exception when unique_violation then
      return jsonb_build_object('__error', 'Data untuk kelompok, sampling, dan tanggal ini sudah ada.', '__status', 409);
    end;
    return jsonb_build_object('id', v_inspection.id);
  end if;

  if p_path ~ '^/api/inspections/[0-9a-fA-F-]+$' then
    v_id := split_part(p_path, '/', 4)::uuid;
    select * into v_inspection from public.inspections where id = v_id;
    if not found then
      return jsonb_build_object('__error', 'Data inspeksi tidak ditemukan.', '__status', 404);
    end if;

    if v_method = 'PATCH' then
      if v_user.role <> 'ADMIN' and v_inspection.inspector_id <> v_user.id then
        return jsonb_build_object('__error', 'Kamu tidak punya izin mengubah data ini.', '__status', 403);
      end if;
      if v_payload ? 'groupId' then
        v_group_id := nullif(v_payload->>'groupId', '')::uuid;
        select name into v_group_name from public.groups_master where id = v_group_id and is_active = true;
      else
        v_group_id := v_inspection.group_id;
        v_group_name := v_inspection.kelompok;
      end if;
      begin
        update public.inspections
        set date = case when v_payload ? 'date' then (v_payload->>'date')::date else date end,
            group_id = v_group_id,
            kelompok = v_group_name,
            brand = case when v_payload ? 'brand' then trim(v_payload->>'brand') else brand end,
            sampling = case when v_payload ? 'sampling' then (v_payload->>'sampling')::integer else sampling end,
            sample_size = case when v_payload ? 'sampleSize' then (v_payload->>'sampleSize')::integer else sample_size end,
            params = case when v_payload ? 'params' then v_payload->'params' else params end
        where id = v_id;
      exception when unique_violation then
        return jsonb_build_object('__error', 'Data duplikat (tanggal + kelompok + sampling).', '__status', 409);
      end;
      return jsonb_build_object('ok', true);
    end if;

    if v_method = 'DELETE' then
      if v_user.role <> 'ADMIN' then
        return jsonb_build_object('__error', 'Hanya Admin yang bisa menghapus.', '__status', 403);
      end if;
      delete from public.inspections where id = v_id;
      return jsonb_build_object('ok', true);
    end if;
  end if;

  -- -------------------- MC TEMBAKAU --------------------
  if p_path = '/api/moisture' and v_method = 'GET' then
    select coalesce(jsonb_agg(item order by item->>'date' desc, item->>'createdAt' desc), '[]'::jsonb)
    into v_result
    from (
      select jsonb_build_object(
        'id', id, 'date', to_char(date, 'YYYY-MM-DD'), 'lotBatch', lot_batch,
        'seriesNumber', series_number, 'brand', brand, 'moistureContent', moisture_content,
        'inspector', inspector, 'inspectorId', inspector_id, 'createdAt', created_at
      ) as item
      from public.moisture_records
    ) q;
    return jsonb_build_object('records', v_result);
  end if;

  if p_path = '/api/moisture' and v_method = 'POST' then
    insert into public.moisture_records
      (date, lot_batch, series_number, brand, moisture_content, inspector, inspector_id)
    values
      ((v_payload->>'date')::date, trim(v_payload->>'lotBatch'), trim(v_payload->>'seriesNumber'),
       trim(v_payload->>'brand'), (v_payload->>'moistureContent')::numeric, v_user.display_name, v_user.id)
    returning * into v_moisture;
    return jsonb_build_object('id', v_moisture.id);
  end if;

  if p_path ~ '^/api/moisture/[0-9a-fA-F-]+$' then
    v_id := split_part(p_path, '/', 4)::uuid;
    select * into v_moisture from public.moisture_records where id = v_id;
    if not found then
      return jsonb_build_object('__error', 'Data MC tidak ditemukan.', '__status', 404);
    end if;
    if v_method = 'PATCH' then
      if v_user.role <> 'ADMIN' and v_moisture.inspector_id <> v_user.id then
        return jsonb_build_object('__error', 'Kamu tidak punya izin mengubah data ini.', '__status', 403);
      end if;
      update public.moisture_records
      set date = case when v_payload ? 'date' then (v_payload->>'date')::date else date end,
          lot_batch = case when v_payload ? 'lotBatch' then trim(v_payload->>'lotBatch') else lot_batch end,
          series_number = case when v_payload ? 'seriesNumber' then trim(v_payload->>'seriesNumber') else series_number end,
          brand = case when v_payload ? 'brand' then trim(v_payload->>'brand') else brand end,
          moisture_content = case when v_payload ? 'moistureContent' then (v_payload->>'moistureContent')::numeric else moisture_content end
      where id = v_id;
      return jsonb_build_object('ok', true);
    end if;
    if v_method = 'DELETE' then
      if v_user.role <> 'ADMIN' then
        return jsonb_build_object('__error', 'Hanya Admin yang bisa menghapus.', '__status', 403);
      end if;
      delete from public.moisture_records where id = v_id;
      return jsonb_build_object('ok', true);
    end if;
  end if;

  -- -------------------- QUALITY PACK --------------------
  if p_path = '/api/pack-quality' and v_method = 'GET' then
    select coalesce(jsonb_agg(item order by item->>'date' desc, item->>'createdAt' desc), '[]'::jsonb)
    into v_result
    from (
      select jsonb_build_object(
        'id', id, 'date', to_char(date, 'YYYY-MM-DD'), 'samplingTime', sampling_time,
        'params', params, 'inspector', inspector, 'inspectorId', inspector_id, 'createdAt', created_at
      ) as item
      from public.pack_records
    ) q;
    return jsonb_build_object('records', v_result);
  end if;

  if p_path = '/api/pack-quality' and v_method = 'POST' then
    insert into public.pack_records
      (date, sampling_time, params, inspector, inspector_id)
    values
      ((v_payload->>'date')::date, trim(v_payload->>'samplingTime'),
       coalesce(v_payload->'params', '{}'::jsonb), v_user.display_name, v_user.id)
    returning * into v_pack;
    return jsonb_build_object('id', v_pack.id);
  end if;

  if p_path ~ '^/api/pack-quality/[0-9a-fA-F-]+$' then
    v_id := split_part(p_path, '/', 4)::uuid;
    select * into v_pack from public.pack_records where id = v_id;
    if not found then
      return jsonb_build_object('__error', 'Data Quality Pack tidak ditemukan.', '__status', 404);
    end if;
    if v_method = 'PATCH' then
      if v_user.role <> 'ADMIN' and v_pack.inspector_id <> v_user.id then
        return jsonb_build_object('__error', 'Kamu tidak punya izin mengubah data ini.', '__status', 403);
      end if;
      update public.pack_records
      set date = case when v_payload ? 'date' then (v_payload->>'date')::date else date end,
          sampling_time = case when v_payload ? 'samplingTime' then trim(v_payload->>'samplingTime') else sampling_time end,
          params = case when v_payload ? 'params' then v_payload->'params' else params end
      where id = v_id;
      return jsonb_build_object('ok', true);
    end if;
    if v_method = 'DELETE' then
      if v_user.role <> 'ADMIN' then
        return jsonb_build_object('__error', 'Hanya Admin yang bisa menghapus.', '__status', 403);
      end if;
      delete from public.pack_records where id = v_id;
      return jsonb_build_object('ok', true);
    end if;
  end if;

  -- -------------------- PENGGUNA --------------------
  if p_path = '/api/users' and v_method = 'GET' then
    if v_user.role <> 'ADMIN' then
      return jsonb_build_object('__error', 'Hanya Admin yang dapat melihat akun.', '__status', 403);
    end if;
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', id, 'displayName', display_name, 'username', username,
      'role', role, 'isActive', is_active
    ) order by created_at), '[]'::jsonb)
    into v_result
    from public.app_users;
    return jsonb_build_object('users', v_result);
  end if;

  if p_path = '/api/users' and v_method = 'POST' then
    if v_user.role <> 'ADMIN' then
      return jsonb_build_object('__error', 'Hanya Admin yang dapat membuat akun.', '__status', 403);
    end if;
    if length(trim(coalesce(v_payload->>'displayName', ''))) < 2
       or trim(coalesce(v_payload->>'username', '')) !~ '^[A-Za-z0-9._-]{3,40}$'
       or length(coalesce(v_payload->>'password', '')) < 8
       or coalesce(v_payload->>'role', '') not in ('ADMIN', 'INSPECTOR') then
      return jsonb_build_object('__error', 'Data akun belum lengkap atau tidak valid.', '__status', 400);
    end if;
    begin
      insert into public.app_users (display_name, username, password_hash, role, is_active)
      values (
        trim(v_payload->>'displayName'), lower(trim(v_payload->>'username')),
        extensions.crypt(v_payload->>'password', extensions.gen_salt('bf', 10)),
        v_payload->>'role', true
      ) returning * into v_target;
    exception when unique_violation then
      return jsonb_build_object('__error', 'Username sudah dipakai.', '__status', 409);
    end;
    return jsonb_build_object('id', v_target.id);
  end if;

  if p_path ~ '^/api/users/[0-9a-fA-F-]+$' and v_method = 'PATCH' then
    if v_user.role <> 'ADMIN' then
      return jsonb_build_object('__error', 'Hanya Admin yang dapat mengubah akun.', '__status', 403);
    end if;
    v_id := split_part(p_path, '/', 4)::uuid;
    if v_id = v_user.id and coalesce((v_payload->>'isActive')::boolean, true) = false then
      return jsonb_build_object('__error', 'Admin tidak dapat menonaktifkan akunnya sendiri.', '__status', 400);
    end if;
    update public.app_users set is_active = (v_payload->>'isActive')::boolean where id = v_id;
    if not found then
      return jsonb_build_object('__error', 'Akun tidak ditemukan.', '__status', 404);
    end if;
    if coalesce((v_payload->>'isActive')::boolean, true) = false then
      delete from public.app_sessions where user_id = v_id;
    end if;
    return jsonb_build_object('ok', true);
  end if;

  -- -------------------- BACKUP BULANAN --------------------
  if p_path = '/api/backup-status' and v_method = 'GET' then
    if v_user.role <> 'ADMIN' then
      return jsonb_build_object('__error', 'Hanya Admin yang dapat melihat status backup.', '__status', 403);
    end if;
    return coalesce((
      select jsonb_build_object('month', month, 'completedAt', completed_at, 'completedBy', completed_by)
      from public.backup_status where id = 1
    ), jsonb_build_object('month', null, 'completedAt', null, 'completedBy', null));
  end if;

  if p_path = '/api/backup-status' and v_method = 'POST' then
    if v_user.role <> 'ADMIN' then
      return jsonb_build_object('__error', 'Hanya Admin yang dapat menyimpan status backup.', '__status', 403);
    end if;
    update public.backup_status
    set month = v_payload->>'month', completed_at = now(), completed_by = v_user.display_name
    where id = 1;
    return (
      select jsonb_build_object('month', month, 'completedAt', completed_at, 'completedBy', completed_by)
      from public.backup_status where id = 1
    );
  end if;

  return jsonb_build_object('__error', 'Endpoint tidak ditemukan.', '__status', 404);

exception when others then
  return jsonb_build_object(
    '__error', 'Database gagal memproses permintaan. Periksa data lalu coba kembali.',
    '__status', 500
  );
end;
$$;

-- Kunci semua tabel dari Data API. Fungsi di atas tetap dapat mengaksesnya
-- karena berjalan sebagai SECURITY DEFINER milik postgres.
alter table public.app_users enable row level security;
alter table public.app_sessions enable row level security;
alter table public.brands enable row level security;
alter table public.groups_master enable row level security;
alter table public.sampling_times enable row level security;
alter table public.app_settings enable row level security;
alter table public.inspections enable row level security;
alter table public.moisture_records enable row level security;
alter table public.pack_records enable row level security;
alter table public.backup_status enable row level security;

revoke all on table
  public.app_users,
  public.app_sessions,
  public.brands,
  public.groups_master,
  public.sampling_times,
  public.app_settings,
  public.inspections,
  public.moisture_records,
  public.pack_records,
  public.backup_status
from anon, authenticated;

revoke all on function public.qc_api_request(text, text, jsonb, text) from public;
grant usage on schema public to anon, authenticated;
grant execute on function public.qc_api_request(text, text, jsonb, text) to anon, authenticated;

-- Hasil akhir yang seharusnya muncul setelah Run:
select 'SETUP SUPABASE SELESAI' as status;
