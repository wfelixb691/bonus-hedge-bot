# 🌐 Cloud Web Dashboard Dual-MT5 Bonus Hedging (v1.23)

Executive Multi-Account Portfolio Console untuk memantau **SEMUA akun client dalam 1 layar** atau navigasi halaman (**Page 1, Page 2, Page 3**) secara realtime langsung dari browser HP & Laptop!

---

## 📱 Fitur Utama Executive Console v1.23:

1. **Portfolio KPI Executive Summary**:
   - **Total Akun Managed**: Status online/offline dan deteksi proteksi realtime.
   - **Total Master & Slave Equity**: Agregat saldo riil seluruh portfolio dalam USD dan Rupiah.
   - **Total Bonus Credit**: Monitor seluruh cadangan amunisi bonus broker.
   - **Portfolio Net Floating**: Gabungan floating PnL seluruh akun client secara simultan.
   - **Net Profit Realized Periodik**: Pilihan periode **[Hari Ini]**, **[Minggu Ini]**, **[Bulan Ini]**, dan **[Semua/Total]**.

2. **Fleksibilitas Tampilan (1 Layar Penuh vs Paged)**:
   - **Tampilan 1 Layar Penuh (All-in-One)**: Menampilkan seluruh akun client sekaligus di layar monitor manager tanpa batasan halaman.
   - **Tampilan Paginated (Page 1, 2, 3)**: Menampilkan 6 kartu akun per halaman secara rapi untuk tablet / HP / monitor standar dengan tombol navigasi `[◀ Prev]` `[ 1 ]` `[ 2 ]` `[ 3 ]` `[ Next ▶]`.
   - **Pencarian Cepat**: Filter akun berdasarkan nama client, Pair ID, atau nomor login MT5.

3. **Multi-Account Card Breakdown**:
   - Perbandingan berdampingan: **Master (Balance, Equity, Float)** vs **Slave (Balance, Equity, Bonus Credit)**.
   - **Badge Status Proteksi**: 🟢 `NORMAL`, 🟡 `SPREAD-LOCK (>60 pt)`, 🔴 `NEWS-PAUSE (CPI/NFP)`.
   - **Net Floating & Realized Net Profit** masing-masing akun beserta konversi Rupiah.
   - **Modal Deep-Dive**: Klik pada kartu akun mana pun untuk melihat rincian tiket hedging, volume lot, harga open, dan net profit per pasang order.

---

## 🚀 Cara Menjalankan:

### Di Komputer / VPS Lokal:
1. Pastikan Node.js terinstall, jalankan di terminal folder ini:
   ```bash
   node server.js
   ```
2. Buka browser: `http://localhost:3000` (atau `http://IP_VPS_ANDA:3000`)

### Deploy Cloud Gratis (Vercel / Render / Railway):
1. Upload folder `cloud_web_dashboard` ke GitHub Anda.
2. Buka [Vercel.com](https://vercel.com) $\rightarrow$ Klik **Add New Project** $\rightarrow$ Pilih repo ini $\rightarrow$ Klik **Deploy**!
3. Dapatkan URL HTTPS publik (contoh: `https://hedge-console.vercel.app`).

---

## ⚙️ Menghubungkan EA Master MT5 ke Web Dashboard:

1. Di MT5 Master, tekan **`F7`** (Setting Input EA):
   * `InpEnableWebDashboard` = **`true`**
   * `InpWebDashboardUrl` = Masukkan URL dashboard + `/api/telemetry`
     *(Contoh: `http://localhost:3000/api/telemetry` atau `https://hedge-console.vercel.app/api/telemetry`)*
   * `InpWebIntervalSec` = **`2`** (Update otomatis setiap 2 detik)
2. Di MT5 Master menu **`Tools` $\rightarrow$ `Options` $\rightarrow$ Tab `Expert Advisors`**:
   * Centang **`Allow WebRequest for listed URL`**.
   * Tambahkan URL server dashboard Anda.
3. Selesai! Dashboard akan otomatis menerima dan menyajikan data seluruh akun client secara terpadu!

