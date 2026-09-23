PEMULIHAN DASHBOARD QUALITY SKT

Repo pada screenshot masih memuat file SKM. Untuk memulihkan web SKT:
1. Ekstrak ZIP ini di komputer. Jangan upload ZIP mentah ke GitHub.
2. Buka repository quality-inspection-qcskt pada folder root yang dipakai GitHub Pages.
3. Hapus dua file SKM dari repo tersebut: skm-app.js dan skm-api.js.
4. Upload file dari paket: index.html, dashboard.html, supabase-config.js, supabase-api.js, dan .nojekyll. Jika browser Windows menyembunyikan .nojekyll, file ini opsional dan yang sudah ada di GitHub boleh dibiarkan.
5. Ganti file lama jika GitHub meminta, lalu Commit changes. Setelah GitHub Pages memperbarui situs, refresh paksa (Ctrl+F5).
6. Aturan database bukan file GitHub: jalankan update-akses-guest-skt.sql di Supabase SQL Editor jika belum dilakukan. Jangan unggah file SQL ke GitHub.

index.html dan dashboard.html SKT mengimpor supabase-config.js dan supabase-api.js. File skm-app.js dan skm-api.js tidak digunakan oleh web SKT ini.
Guest Eksternal: Quality saja. Guest Internal: Quality dan Produksi, baca saja. Admin dan Inspector: sesuai role.
