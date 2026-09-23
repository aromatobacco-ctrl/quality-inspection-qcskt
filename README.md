# Dashboard Quality Inspection SKM · v1.4.3

Dashboard SKM mandiri untuk GitHub Pages dan Supabase, dengan alur login seperti dashboard SKT: **Setup Admin Pertama**, login username/password, serta empat tingkat akses.

## File yang harus ada di GitHub

| File | Kegunaan |
| --- | --- |
| `index.html` | Tampilan login dan dashboard |
| `skm-app.js` | Form, dashboard, grafik, serta pengelolaan akun |
| `skm-api.js` | Penghubung aman antara halaman dan fungsi Supabase |
| `supabase-config.js` | URL dan publishable key project SKM |
| `.nojekyll` | Pendukung GitHub Pages |

`supabase-setup.sql` cukup dijalankan di Supabase. File itu tidak harus diunggah ke GitHub.

## 1. Jalankan database Supabase

1. Buka project Supabase SKM.
2. Pilih **SQL Editor → New query**.
3. Salin seluruh isi `supabase-setup.sql`.
4. Tempel lalu klik **Run**.
5. Hasil akhirnya harus menampilkan `SETUP LOGIN DAN DATABASE SKM SELESAI`.

Skrip membuat tabel akun, sesi login, data inspeksi, dan fungsi API SKM. Password disimpan dalam bentuk hash, bukan teks asli. Tabel tidak dapat dibaca langsung memakai publishable key; akses hanya melalui fungsi yang memeriksa sesi dan role.

## 2. Upload file ke GitHub

Unggah atau replace file berikut pada root repository `quality-inspection-skm`:

- `index.html`
- `skm-app.js`
- `skm-api.js`
- `supabase-config.js`
- `.nojekyll`

Pastikan nama file persis sama dan tidak berubah menjadi `(1)` atau `(2)`.

## 3. Buat Admin pertama

1. Buka halaman GitHub Pages SKM.
2. Klik **Setup Admin Pertama**.
3. Isi nama Admin, username, dan password minimal 8 karakter yang mengandung huruf dan angka.
4. Klik **Buat Admin Pertama**.
5. Admin otomatis masuk ke dashboard.

Setup hanya dapat dilakukan satu kali. Setelah akun pertama terbentuk, tombol setup akan hilang.

## 4. Buat akun tim

Admin membuka menu **Pengaturan**, lalu mengisi nama, username, password sementara, dan role:

| Role | Akses |
| --- | --- |
| `ADMIN` | Dashboard, input, riwayat, hapus data, dan kelola akun |
| `INSPECTOR` | Dashboard, input, riwayat, serta hapus data miliknya sendiri |
| `GUEST_INTERNAL` | Viewer internal: melihat Dashboard dan Data Inspeksi, tanpa input, hapus, atau Pengaturan |
| `GUEST_EXTERNAL` | Viewer eksternal: hanya melihat Dashboard dan data akumulasi |

Admin dapat menonaktifkan akun tanpa menghapus histori inspeksinya. Login dapat digunakan pada beberapa perangkat; setiap sesi berakhir setelah 12 jam.

## 5. Cek cepat

1. Login sebagai Admin.
2. Buat satu akun QC Inspector di Pengaturan.
3. Login menggunakan akun QC dan simpan satu inspeksi Maker atau Packaging.
4. Klik **Segarkan** dan pastikan data tampil di dashboard.
5. Login sebagai Guest Internal dan pastikan Dashboard serta Data Inspeksi terlihat.
6. Login sebagai Guest External dan pastikan hanya menu Dashboard yang terlihat.

Jika halaman menyebut database belum siap, jalankan kembali `supabase-setup.sql` versi v1.4.3. File lama `skm_members` dan `skm_inspections`, bila pernah dibuat, tidak dihapus; versi ini memakai tabel baru agar data lama tidak rusak.

Developed @MT2026 · Last Version: v1.4.3 · 23 September 2026.
