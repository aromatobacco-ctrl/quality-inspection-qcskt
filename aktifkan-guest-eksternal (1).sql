-- Guest Internal = GUEST (akun lama tetap berlaku).
-- Guest Eksternal = DASHBOARD_VIEWER.
-- Perbaikan trend berat: titik agregat per tanggal + jam sampling + brand.
-- Jalankan SELURUH file di Supabase > SQL Editor > New query > Run.
-- Patch membaca fungsi yang terpasang: tidak menimpa perubahan login multi-device.
-- Tidak menghapus akun, sesi, atau data produksi. Pasangkan dengan dashboard.html terbaru.
BEGIN;

CREATE OR REPLACE FUNCTION public.qc_guest_number_v1(value text)
RETURNS numeric LANGUAGE sql IMMUTABLE SET search_path = pg_catalog AS $fn$
 SELECT CASE WHEN trim(value) ~ '^[+]?[0-9]+([.][0-9]+)?$' THEN trim(value)::numeric ELSE NULL END;
$fn$;
REVOKE ALL ON FUNCTION public.qc_guest_number_v1(text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.qc_guest_summary_v1(start_date date, end_date date)
RETURNS jsonb LANGUAGE sql STABLE SET search_path = public, pg_catalog AS $fn$
WITH base AS (
 SELECT date,brand,sample_size,params,sampling,
 coalesce((SELECT st.time_label FROM public.sampling_times st WHERE st.sampling_no=inspections.sampling LIMIT 1),
 CASE sampling WHEN 1 THEN '08:00' WHEN 2 THEN '10:00' WHEN 3 THEN '13:00' ELSE 'Sampling ' || sampling::text END) AS sampling_time,
 coalesce(
 nullif(public.qc_guest_number_v1(params->>'averageWeight'),0),
 nullif(public.qc_guest_number_v1(params->>'weightAverage'),0),
 nullif(public.qc_guest_number_v1(params->>'avgWeight'),0),
 (SELECT CASE WHEN count(*)=5 AND count(nullif(public.qc_guest_number_v1(value),0))=5
    THEN avg(nullif(public.qc_guest_number_v1(value),0)) END
  FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(params->'weightSamples')='array'
    THEN params->'weightSamples' ELSE jsonb_build_array(params->'weight1',params->'weight2',params->'weight3',params->'weight4',params->'weight5') END)
  WITH ORDINALITY AS w(value,idx) WHERE idx<=5)
 ) AS weight
 FROM public.inspections WHERE date BETWEEN start_date AND end_date
), gparams AS (
 SELECT date,brand,sample_size,k,public.qc_guest_number_v1(params->>k) AS value
 FROM base CROSS JOIN unnest(ARRAY['gtg','krps','kmls','ring','bst','spt','krt','brt','dmt']) k
), pack_config(station,metric,keys,capacity) AS (VALUES
('PACKING','foldNotSquare',ARRAY['foldNotSquare']::text[],10),
('PACKING','depositGlue',ARRAY['depositGlue','insufficientGlue']::text[],10),
('PACKING','innerFrame',ARRAY['innerFrame']::text[],10),
('PACKING','cigarettePosition',ARRAY['cigarettePosition']::text[],10),
('BANDROLL','depositGlue',ARRAY['depositGlue']::text[],10),
('BANDROLL','taxStampPosition',ARRAY['taxStampPosition','banderolPosition']::text[],10),
('OPP','heating',ARRAY['heating','overheating']::text[],10),
('OPP','tearTapeAccess',ARRAY['tearTapeAccess']::text[],10),
('OPP','fold',ARRAY['fold','oppFold']::text[],10),
('OPP','cleanliness',ARRAY['cleanliness']::text[],10),
('MOP','heating',ARRAY['heating','overheating']::text[],5),
('MOP','tearTapeAccess',ARRAY['tearTapeAccess']::text[],5),
('MOP','fold',ARRAY['fold']::text[],5),
('MOP','barcodeStickerPosition',ARRAY['barcodeStickerPosition']::text[],5),
('MOP','barcodeStickerNeatness',ARRAY['barcodeStickerNeatness']::text[],5),
('MOP','cleanliness',ARRAY['cleanliness']::text[],5)
), pack_base AS (
 SELECT date,params,CASE replace(upper(trim(coalesce(params->>'stationType',params->>'station','PACKING'))),' ','')
 WHEN 'BANDEROL' THEN 'BANDROLL' WHEN 'BANDROLL' THEN 'BANDROLL'
 WHEN 'OPP' THEN 'OPP' WHEN 'MOP' THEN 'MOP' ELSE 'PACKING' END AS station
 FROM public.pack_records WHERE date BETWEEN start_date AND end_date
), pparams AS (
 SELECT b.date,b.station,c.metric,c.capacity,
 (SELECT public.qc_guest_number_v1(b.params->>key)
  FROM unnest(c.keys) WITH ORDINALITY AS a(key,idx)
  WHERE public.qc_guest_number_v1(b.params->>key) IS NOT NULL ORDER BY idx LIMIT 1) AS value
 FROM pack_base b JOIN pack_config c ON c.station=b.station
), metrics AS (
 SELECT date,coalesce(brand,'') AS brand,'GILING'::text AS station,k AS metric,
 sum(value) AS numerator,sum(sample_size) FILTER (WHERE value IS NOT NULL)::numeric AS denominator
 FROM gparams GROUP BY date,brand,k
 UNION ALL
 SELECT date,coalesce(brand,''),'GILING','weight',sum(weight),count(weight)::numeric FROM base GROUP BY date,brand
 UNION ALL
 SELECT date,coalesce(brand,''),'GILING','samples',sum(sample_size),1::numeric FROM base GROUP BY date,brand
 UNION ALL
 SELECT date,coalesce(brand,''),'GILING','records',count(*)::numeric,1::numeric FROM base GROUP BY date,brand
 UNION ALL
 SELECT date,'',station,metric,sum(value),sum(capacity) FILTER (WHERE value IS NOT NULL)::numeric
 FROM pparams GROUP BY date,station,metric
 UNION ALL
 SELECT date,'',station,'records',count(*)::numeric,1::numeric FROM pack_base GROUP BY date,station
 UNION ALL
 SELECT date,coalesce(brand,''),CASE WHEN upper(split_part(coalesce(lot_batch,''),'|',1))='PEMAKAIAN' THEN 'USAGE' ELSE 'RECEIVING' END,
 'mc',sum(moisture_content),count(moisture_content)::numeric
 FROM public.moisture_records WHERE date BETWEEN start_date AND end_date
 GROUP BY date,brand,CASE WHEN upper(split_part(coalesce(lot_batch,''),'|',1))='PEMAKAIAN' THEN 'USAGE' ELSE 'RECEIVING' END
)
SELECT jsonb_build_object('schemaVersion',1,'metrics',coalesce((
 SELECT jsonb_agg(jsonb_build_object('date',to_char(date,'YYYY-MM-DD'),'brand',brand,'station',station,
 'metric',metric,'numerator',numerator,'denominator',denominator) ORDER BY date,station,brand,metric) FROM metrics
),'[]'::jsonb),'weightTrendVersion',1,'weightTrend',coalesce((
 SELECT jsonb_agg(jsonb_build_object('date',to_char(date,'YYYY-MM-DD'),'brand',brand,
 'samplingTime',sampling_time,'numerator',numerator,'denominator',denominator)
 ORDER BY date,sampling_time,brand)
 FROM (
   SELECT date,coalesce(brand,'') AS brand,sampling_time,sum(weight) AS numerator,count(weight) AS denominator
   FROM base WHERE weight IS NOT NULL GROUP BY date,brand,sampling_time
 ) trend
),'[]'::jsonb),'wasteAvailable',false);
$fn$;
REVOKE ALL ON FUNCTION public.qc_guest_summary_v1(date,date) FROM PUBLIC, anon, authenticated;

DO $patch$
DECLARE
 definition text;
 updated text;
 constraint_row record;
 old_roles constant text := $roles$('ADMIN', 'INSPECTOR', 'GUEST')$roles$;
 new_roles constant text := $roles$('ADMIN', 'INSPECTOR', 'GUEST', 'DASHBOARD_VIEWER')$roles$;
 anchor constant text := $anchor$  if v_user.role = 'GUEST' and v_method <> 'GET' then$anchor$;
 gate constant text := $gate$
  -- QC_GUEST_EXTERNAL_AGGREGATES_V1: setelah validasi sesi dan logout.
  if v_user.role = 'DASHBOARD_VIEWER' then
    if p_path <> '/api/dashboard-summary' or v_method <> 'GET' then
      return jsonb_build_object('__error','Guest Eksternal hanya dapat mengakses ringkasan dashboard.','__status',403);
    end if;
    if coalesce(v_payload->>'start','') !~ '^\d{4}-\d{2}-\d{2}$'
       or coalesce(v_payload->>'end','') !~ '^\d{4}-\d{2}-\d{2}$' then
      return jsonb_build_object('__error','Pilih tanggal mulai dan selesai.','__status',400);
    end if;
    if (v_payload->>'end')::date < (v_payload->>'start')::date
       or (v_payload->>'end')::date - (v_payload->>'start')::date > 366 then
      return jsonb_build_object('__error','Rentang tanggal maksimal 367 hari.','__status',400);
    end if;
    return public.qc_guest_summary_v1((v_payload->>'start')::date,(v_payload->>'end')::date);
  end if;
$gate$;
BEGIN
 IF to_regprocedure('public.qc_api_request(text,text,jsonb,text)') IS NULL THEN
   RAISE EXCEPTION 'qc_api_request belum terpasang. Patch dibatalkan.';
 END IF;
 SELECT pg_get_functiondef('public.qc_api_request(text,text,jsonb,text)'::regprocedure) INTO definition;
 IF strpos(definition,'QC_GUEST_EXTERNAL_AGGREGATES_V1')=0 THEN
   IF strpos(definition,anchor)=0 OR strpos(definition,old_roles)=0
      OR strpos(definition,anchor)<strpos(definition,'if v_user.id is null then')
      OR strpos(definition,'if v_user.id is null then')=0 THEN
     RAISE EXCEPTION 'Versi fungsi berbeda dari file yang diperiksa; tidak ada perubahan diterapkan.';
   END IF;
   updated := replace(replace(definition,old_roles,new_roles),anchor,gate || chr(10) || anchor);
   EXECUTE updated;
 END IF;
 -- Hanya constraint check yang secara khusus mengatur kolom role.
 FOR constraint_row IN
   SELECT c.conname FROM pg_constraint c
   JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attname='role'
   WHERE c.conrelid='public.app_users'::regclass AND c.contype='c' AND c.conkey=ARRAY[a.attnum]::smallint[]
 LOOP
   EXECUTE format('ALTER TABLE public.app_users DROP CONSTRAINT %I',constraint_row.conname);
 END LOOP;
 ALTER TABLE public.app_users ADD CONSTRAINT app_users_role_check
 CHECK (role IN ('ADMIN','INSPECTOR','GUEST','DASHBOARD_VIEWER'));
END;
$patch$;

-- Browser hanya boleh memakai RPC yang memvalidasi sesi, bukan membaca tabel langsung.
REVOKE ALL ON TABLE public.app_users,public.app_sessions,public.brands,public.groups_master,
 public.sampling_times,public.app_settings,public.inspections,public.moisture_records,
 public.pack_records,public.backup_status FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.qc_api_request(text,text,jsonb,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.qc_api_request(text,text,jsonb,text) TO anon,authenticated;
COMMIT;
SELECT 'Guest Internal dan Guest Eksternal siap. Gunakan dashboard.html terbaru.' AS hasil;
