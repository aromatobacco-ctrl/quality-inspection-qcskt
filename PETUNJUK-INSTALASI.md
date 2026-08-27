# Quality Inspection SKT — GitHub Pages + Supabase

Versi ini tidak memakai Render, kartu Visa, server Node.js, atau `DATABASE_URL`.
GitHub Pages menampilkan dashboard dan Supabase menyimpan data bersama.

## A. Siapkan fungsi database

1. Pastikan file `db/schema.sql` dari paket backend sebelumnya sudah berhasil
   dijalankan di Supabase. Ini sudah dilakukan jika tabel `app_users`, `brands`,
   `groups_master`, `inspections`, `moisture_records`, dan `pack_records` terlihat
   di **Table Editor**.
2. Buka Supabase → **SQL Editor** → **New query**.
3. Buka file `supabase-setup.sql` dari paket ini menggunakan Notepad.
4. Tekan `Ctrl + A`, lalu `Ctrl + C`.
5. Tempel ke SQL Editor dan klik **Run**.
6. Jika muncul peringatan RLS, pilih **Run and enable RLS**.
7. Setup berhasil jika hasil bawah menampilkan `SETUP SUPABASE SELESAI`.

## B. Ambil Publishable Key

1. Di Supabase buka **Project Settings** → **API Keys**.
2. Salin key yang berlabel **Publishable key** (`sb_publishable_...`).
3. Jangan menggunakan `Secret key` atau `service_role`.
4. Buka file `supabase-config.js` menggunakan Notepad.
5. Ganti teks berikut:

   ```text
   PASTE_SUPABASE_PUBLISHABLE_KEY_HERE
   ```

   dengan Publishable key, tanpa mengubah tanda petik.
6. Simpan file dengan `Ctrl + S`.

Publishable key memang aman berada di frontend. Tabel tetap dikunci oleh RLS,
dan operasi hanya dapat dilakukan melalui fungsi database yang memeriksa sesi.

## C. Upload ke GitHub Pages

1. Buka repository GitHub Pages:
   `aromatobacco-ctrl/quality-inspection-qcskt`.
2. Klik **Add file** → **Upload files**.
3. Upload seluruh isi folder paket ini, bukan ZIP-nya:

   - `.nojekyll`
   - `index.html`
   - `dashboard.html`
   - `supabase-config.js`
   - `supabase-api.js`
   - `supabase-setup.sql`
   - `PETUNJUK-INSTALASI.md`

4. Jika GitHub memberi peringatan bahwa file dengan nama sama akan diganti,
   lanjutkan karena memang ini versi baru.
5. Klik **Commit changes**.
6. Tunggu 1–5 menit, lalu buka:
   `https://aromatobacco-ctrl.github.io/quality-inspection-qcskt/`.

## D. Buat Admin pertama

1. Pada halaman login klik **Setup Admin Pertama**.
2. Isi nama, username, dan password minimal 8 karakter.
3. Klik **Buat Admin Pertama**.
4. Fitur ini hanya dapat dipakai satu kali. Setelah Admin pertama terbentuk,
   permintaan setup berikutnya otomatis ditolak.

## E. Buat akun QC Inspector

1. Login sebagai Admin.
2. Buka menu **Pengaturan**.
3. Pada **Akun Pengguna**, klik tambah pengguna.
4. Isi nama, username, password, dan pilih role **QC Inspector**.
5. Inspector dapat memasukkan serta mengoreksi datanya sendiri. Admin dapat
   mengelola seluruh data dan pengguna.

## Catatan keamanan

- Jangan pernah memasukkan `DATABASE_URL`, password database, Secret key, atau
  `service_role` ke GitHub.
- Sesi login berlaku 12 jam.
- Lima kali password salah mengunci akun selama 15 menit.
- Lakukan backup XLSX bulanan melalui dashboard.
