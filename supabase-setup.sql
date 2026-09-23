-- QUALITY INSPECTION SKM v1.4.3
-- Jalankan seluruh file ini di Supabase > SQL Editor > Run.
-- Login mengikuti dashboard SKT: setup Admin pertama, username/password, dan role.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.skm_app_users (
  id uuid primary key default extensions.gen_random_uuid(),
  display_name text not null check (length(trim(display_name)) between 2 and 80),
  username text not null check (username ~ '^[A-Za-z0-9._-]{3,40}$'),
  password_hash text not null,
  role text not null,
  is_active boolean not null default true,
  failed_login_count integer not null default 0,
  locked_until timestamptz,
  created_at timestamptz not null default now()
);

-- Migrasi role dari versi sebelumnya tanpa menghapus akun yang sudah ada.
alter table public.skm_app_users drop constraint if exists skm_app_users_role_check;
update public.skm_app_users set role='GUEST_EXTERNAL' where role='GUEST';
alter table public.skm_app_users add constraint skm_app_users_role_check
  check (role in ('ADMIN','INSPECTOR','GUEST_INTERNAL','GUEST_EXTERNAL'));

create unique index if not exists skm_users_username_lower_unique
  on public.skm_app_users (lower(username));

create table if not exists public.skm_app_sessions (
  token_hash text primary key,
  user_id uuid not null references public.skm_app_users(id) on delete cascade,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index if not exists skm_sessions_user_idx on public.skm_app_sessions(user_id);
create index if not exists skm_sessions_expiry_idx on public.skm_app_sessions(expires_at);

create table if not exists public.skm_quality_inspections (
  id uuid primary key default extensions.gen_random_uuid(),
  author_id uuid not null references public.skm_app_users(id) on delete restrict,
  station text not null check (station in ('Maker','Packer')),
  sample_date date not null,
  sample_time time without time zone not null,
  qc_name text not null,
  shift text not null check (shift in ('Shift 1','Shift 2','Shift 3')),
  brand text not null check (brand in ('AMB','AMT','ARM','ARB12','ARB16')),
  machine text not null,
  sample_count integer not null check (sample_count between 1 and 10000),
  physical jsonb not null default '{}'::jsonb,
  visual jsonb not null default '{}'::jsonb,
  no_finding boolean not null default false,
  trouble_point text not null default '',
  notes text not null default '',
  production_code text not null default '',
  cigarettes_per_pack integer,
  pack_count integer,
  created_at timestamptz not null default now(),
  check ((station='Maker' and machine in ('M1','M2','M3','M4','M5')) or
         (station='Packer' and machine in ('P1','P2','P3','P4','P5','P6','Focke'))),
  check (extract(minute from sample_time)=0 and extract(second from sample_time)=0),
  check (jsonb_typeof(physical)='object' and jsonb_typeof(visual)='object'),
  check (length(trouble_point)<=500 and length(notes)<=500)
);
create index if not exists skm_quality_date_idx
  on public.skm_quality_inspections(sample_date desc, sample_time desc);
create index if not exists skm_quality_author_idx
  on public.skm_quality_inspections(author_id);

create or replace function public.skm_api_request(
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
  v_user public.skm_app_users%rowtype;
  v_target public.skm_app_users%rowtype;
  v_record public.skm_quality_inspections%rowtype;
  v_method text := upper(coalesce(p_method,'GET'));
  v_payload jsonb := coalesce(p_payload,'{}'::jsonb);
  v_result jsonb;
  v_token text;
  v_token_hash text;
  v_id uuid;
  v_failed integer;
begin
  delete from public.skm_app_sessions where expires_at <= now();

  if p_path='/api/auth/status' and v_method='GET' then
    if coalesce(p_session_token,'')='' then
      return jsonb_build_object('user',null,'needsBootstrap',not exists(select 1 from public.skm_app_users));
    end if;
    select u.* into v_user from public.skm_app_sessions s
      join public.skm_app_users u on u.id=s.user_id
      where s.token_hash=encode(extensions.digest(p_session_token,'sha256'),'hex')
        and s.expires_at>now() and u.is_active;
    if not found then
      return jsonb_build_object('user',null,'needsBootstrap',not exists(select 1 from public.skm_app_users),'clearSession',true);
    end if;
    return jsonb_build_object('needsBootstrap',false,'user',jsonb_build_object(
      'id',v_user.id,'displayName',v_user.display_name,'username',v_user.username,
      'role',v_user.role,'isActive',v_user.is_active));
  end if;

  if p_path='/api/auth/bootstrap' and v_method='POST' then
    lock table public.skm_app_users in exclusive mode;
    if exists(select 1 from public.skm_app_users) then
      return jsonb_build_object('__error','Admin pertama sudah dibuat. Silakan login.','__status',409);
    end if;
    if length(trim(coalesce(v_payload->>'displayName','')))<2 then
      return jsonb_build_object('__error','Nama Admin wajib diisi.','__status',400);
    end if;
    if trim(coalesce(v_payload->>'username','')) !~ '^[A-Za-z0-9._-]{3,40}$' then
      return jsonb_build_object('__error','Username harus 3–40 karakter: huruf, angka, titik, garis bawah, atau strip.','__status',400);
    end if;
    if length(coalesce(v_payload->>'password',''))<8
       or coalesce(v_payload->>'password','') !~ '[A-Za-z]'
       or coalesce(v_payload->>'password','') !~ '[0-9]' then
      return jsonb_build_object('__error','Password minimal 8 karakter serta mengandung huruf dan angka.','__status',400);
    end if;
    insert into public.skm_app_users(display_name,username,password_hash,role,is_active)
    values(trim(v_payload->>'displayName'),lower(trim(v_payload->>'username')),
      extensions.crypt(v_payload->>'password',extensions.gen_salt('bf',10)),'ADMIN',true)
    returning * into v_user;
    v_token:=encode(extensions.gen_random_bytes(32),'hex');
    v_token_hash:=encode(extensions.digest(v_token,'sha256'),'hex');
    insert into public.skm_app_sessions(token_hash,user_id,expires_at)
    values(v_token_hash,v_user.id,now()+interval '12 hours');
    return jsonb_build_object('sessionToken',v_token,'user',jsonb_build_object(
      'id',v_user.id,'displayName',v_user.display_name,'username',v_user.username,
      'role',v_user.role,'isActive',v_user.is_active));
  end if;

  if p_path='/api/auth/login' and v_method='POST' then
    select * into v_target from public.skm_app_users
      where lower(username)=lower(trim(coalesce(v_payload->>'username',''))) limit 1;
    if not found or not v_target.is_active then
      return jsonb_build_object('__error','Username atau password salah, atau akun nonaktif.','__status',401);
    end if;
    if v_target.locked_until is not null and v_target.locked_until>now() then
      return jsonb_build_object('__error','Akun dikunci sementara. Coba lagi 15 menit kemudian.','__status',429);
    end if;
    if v_target.password_hash<>extensions.crypt(coalesce(v_payload->>'password',''),v_target.password_hash) then
      v_failed:=coalesce(v_target.failed_login_count,0)+1;
      update public.skm_app_users set
        failed_login_count=case when v_failed>=5 then 0 else v_failed end,
        locked_until=case when v_failed>=5 then now()+interval '15 minutes' else null end
      where id=v_target.id;
      return jsonb_build_object('__error','Username atau password salah, atau akun nonaktif.','__status',401);
    end if;
    update public.skm_app_users set failed_login_count=0,locked_until=null where id=v_target.id returning * into v_user;
    v_token:=encode(extensions.gen_random_bytes(32),'hex');
    v_token_hash:=encode(extensions.digest(v_token,'sha256'),'hex');
    insert into public.skm_app_sessions(token_hash,user_id,expires_at)
    values(v_token_hash,v_user.id,now()+interval '12 hours');
    return jsonb_build_object('sessionToken',v_token,'user',jsonb_build_object(
      'id',v_user.id,'displayName',v_user.display_name,'username',v_user.username,
      'role',v_user.role,'isActive',v_user.is_active));
  end if;

  if coalesce(p_session_token,'')<>'' then
    select u.* into v_user from public.skm_app_sessions s
      join public.skm_app_users u on u.id=s.user_id
      where s.token_hash=encode(extensions.digest(p_session_token,'sha256'),'hex')
        and s.expires_at>now() and u.is_active;
  end if;
  if v_user.id is null then
    return jsonb_build_object('__error','Sesi berakhir. Silakan login kembali.','__status',401,'clearSession',true);
  end if;

  if p_path='/api/auth/logout' and v_method='POST' then
    delete from public.skm_app_sessions where token_hash=encode(extensions.digest(p_session_token,'sha256'),'hex');
    return jsonb_build_object('ok',true,'clearSession',true);
  end if;

  if p_path='/api/inspections' and v_method='GET' then
    select coalesce(jsonb_agg(item order by item->>'date' desc,item->>'time' desc),'[]'::jsonb) into v_result
    from (select jsonb_build_object(
      'id',i.id,'authorId',i.author_id,'source','Supabase','type',i.station,
      'date',to_char(i.sample_date,'YYYY-MM-DD'),'time',to_char(i.sample_time,'HH24:MI'),
      'qc',i.qc_name,'shift',i.shift,'brand',i.brand,'machine',i.machine,
      'sample',i.sample_count,'physical',i.physical,'visual',i.visual,
      'noFinding',i.no_finding,'trouble',i.trouble_point,'notes',i.notes,
      'code',i.production_code,'cigarettes',i.cigarettes_per_pack,'packCount',i.pack_count
    ) item from public.skm_quality_inspections i) q;
    return jsonb_build_object('inspections',v_result);
  end if;

  if p_path='/api/inspections' and v_method='POST' then
    if v_user.role not in ('ADMIN','INSPECTOR') then
      return jsonb_build_object('__error','Akun viewer tidak memiliki izin mengisi data.','__status',403);
    end if;
    insert into public.skm_quality_inspections(
      author_id,station,sample_date,sample_time,qc_name,shift,brand,machine,sample_count,
      physical,visual,no_finding,trouble_point,notes,production_code,cigarettes_per_pack,pack_count)
    values(v_user.id,v_payload->>'type',(v_payload->>'date')::date,(v_payload->>'time')::time,
      v_user.display_name,v_payload->>'shift',v_payload->>'brand',v_payload->>'machine',
      (v_payload->>'sample')::integer,coalesce(v_payload->'physical','{}'::jsonb),
      coalesce(v_payload->'visual','{}'::jsonb),coalesce((v_payload->>'noFinding')::boolean,false),
      left(coalesce(v_payload->>'trouble',''),500),left(coalesce(v_payload->>'notes',''),500),
      left(coalesce(v_payload->>'code',''),100),nullif(v_payload->>'cigarettes','')::integer,
      nullif(v_payload->>'packCount','')::integer)
    returning * into v_record;
    return jsonb_build_object('id',v_record.id);
  end if;

  if p_path ~ '^/api/inspections/[0-9a-fA-F-]+$' and v_method='DELETE' then
    v_id:=split_part(p_path,'/',4)::uuid;
    select * into v_record from public.skm_quality_inspections where id=v_id;
    if not found then return jsonb_build_object('__error','Data inspeksi tidak ditemukan.','__status',404); end if;
    if v_user.role<>'ADMIN' and not (v_user.role='INSPECTOR' and v_record.author_id=v_user.id) then
      return jsonb_build_object('__error','Kamu tidak memiliki izin menghapus data ini.','__status',403);
    end if;
    delete from public.skm_quality_inspections where id=v_id;
    return jsonb_build_object('ok',true);
  end if;

  if p_path='/api/users' and v_method='GET' then
    if v_user.role<>'ADMIN' then return jsonb_build_object('__error','Hanya Admin yang dapat melihat akun.','__status',403); end if;
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',id,'displayName',display_name,'username',username,'role',role,'isActive',is_active
    ) order by created_at),'[]'::jsonb) into v_result from public.skm_app_users;
    return jsonb_build_object('users',v_result);
  end if;

  if p_path='/api/users' and v_method='POST' then
    if v_user.role<>'ADMIN' then return jsonb_build_object('__error','Hanya Admin yang dapat membuat akun.','__status',403); end if;
    if length(trim(coalesce(v_payload->>'displayName','')))<2
       or trim(coalesce(v_payload->>'username','')) !~ '^[A-Za-z0-9._-]{3,40}$'
       or coalesce(v_payload->>'role','') not in ('ADMIN','INSPECTOR','GUEST_INTERNAL','GUEST_EXTERNAL') then
      return jsonb_build_object('__error','Nama, username, atau role akun tidak valid.','__status',400);
    end if;
    if length(coalesce(v_payload->>'password',''))<8
       or coalesce(v_payload->>'password','') !~ '[A-Za-z]'
       or coalesce(v_payload->>'password','') !~ '[0-9]' then
      return jsonb_build_object('__error','Password minimal 8 karakter serta mengandung huruf dan angka.','__status',400);
    end if;
    begin
      insert into public.skm_app_users(display_name,username,password_hash,role,is_active)
      values(trim(v_payload->>'displayName'),lower(trim(v_payload->>'username')),
        extensions.crypt(v_payload->>'password',extensions.gen_salt('bf',10)),v_payload->>'role',true)
      returning * into v_target;
    exception when unique_violation then
      return jsonb_build_object('__error','Username sudah dipakai.','__status',409);
    end;
    return jsonb_build_object('id',v_target.id);
  end if;

  if p_path ~ '^/api/users/[0-9a-fA-F-]+$' and v_method='PATCH' then
    if v_user.role<>'ADMIN' then return jsonb_build_object('__error','Hanya Admin yang dapat mengubah akun.','__status',403); end if;
    v_id:=split_part(p_path,'/',4)::uuid;
    if v_id=v_user.id and coalesce((v_payload->>'isActive')::boolean,true)=false then
      return jsonb_build_object('__error','Admin tidak dapat menonaktifkan akunnya sendiri.','__status',400);
    end if;
    update public.skm_app_users set is_active=coalesce((v_payload->>'isActive')::boolean,is_active) where id=v_id;
    if not found then return jsonb_build_object('__error','Akun tidak ditemukan.','__status',404); end if;
    if coalesce((v_payload->>'isActive')::boolean,true)=false then
      delete from public.skm_app_sessions where user_id=v_id;
    end if;
    return jsonb_build_object('ok',true);
  end if;

  return jsonb_build_object('__error','Endpoint tidak ditemukan.','__status',404);
exception when others then
  return jsonb_build_object('__error','Database gagal memproses permintaan: '||sqlerrm,'__status',500);
end;
$$;

alter table public.skm_app_users enable row level security;
alter table public.skm_app_sessions enable row level security;
alter table public.skm_quality_inspections enable row level security;

revoke all on table public.skm_app_users,public.skm_app_sessions,public.skm_quality_inspections from anon,authenticated;
revoke all on function public.skm_api_request(text,text,jsonb,text) from public;
grant usage on schema public to anon,authenticated;
grant execute on function public.skm_api_request(text,text,jsonb,text) to anon,authenticated;

select 'SETUP LOGIN DAN DATABASE SKM SELESAI' as status;
