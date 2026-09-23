-- SKT: Guest Eksternal hanya Quality; Guest Internal melihat Quality dan Produksi.
-- Jalankan sekali di Supabase SQL Editor setelah aktifkan-guest-eksternal.sql
-- dan waste-supabase.sql sudah dipasang. Aman dijalankan ulang.
BEGIN;
DO $patch$
DECLARE
  definition text;
  updated text;
  old_branch constant text := $old$if u.role in ('DASHBOARD_VIEWER','GUEST') then$old$;
  new_branch constant text := $new$if u.role = 'DASHBOARD_VIEWER' then$new$;
  old_get constant text := $oldget$if method='GET' then$oldget$;
  guarded_get constant text := $newget$-- SKT_GUEST_PRODUCTION_ACCESS_V1
 if u.role = 'DASHBOARD_VIEWER' then
  return jsonb_build_object('__error','Guest Eksternal tidak memiliki akses ke data Produksi.','__status',403);
 end if;
 if method='GET' then$newget$;
BEGIN
  IF to_regprocedure('public.qc_api_request(text,text,jsonb,text)') IS NULL
     OR to_regprocedure('public.qc_waste_request(text,jsonb,text)') IS NULL THEN
    RAISE EXCEPTION 'Fungsi API SKT belum lengkap; pasang patch Guest Eksternal dan Waste terlebih dahulu.';
  END IF;
  SELECT pg_get_functiondef('public.qc_api_request(text,text,jsonb,text)'::regprocedure) INTO definition;
  IF strpos(definition,'QC_GUEST_EXTERNAL_AGGREGATES_V1') = 0 THEN
    RAISE EXCEPTION 'Pembatasan Quality untuk Guest Eksternal belum terpasang. Jalankan aktifkan-guest-eksternal.sql dahulu.';
  END IF;
  SELECT pg_get_functiondef('public.qc_waste_request(text,jsonb,text)'::regprocedure) INTO definition;
  IF strpos(definition,'SKT_GUEST_PRODUCTION_ACCESS_V1') = 0 THEN
    IF strpos(definition,old_branch) = 0 OR strpos(definition,old_get) = 0 THEN
      RAISE EXCEPTION 'Versi fungsi Waste berbeda. Patch dibatalkan tanpa mengubah database.';
    END IF;
    updated := replace(definition,old_branch,new_branch);
    updated := replace(updated,old_get,guarded_get);
    EXECUTE updated;
  END IF;
END;
$patch$;
COMMIT;
-- Pemeriksaan setelah Run: nilai harus true.
SELECT pg_get_functiondef('public.qc_api_request(text,text,jsonb,text)'::regprocedure)
       LIKE '%QC_GUEST_EXTERNAL_AGGREGATES_V1%' AS guest_external_quality_only,
       pg_get_functiondef('public.qc_waste_request(text,jsonb,text)'::regprocedure)
       LIKE '%SKT_GUEST_PRODUCTION_ACCESS_V1%' AS guest_external_production_blocked;
