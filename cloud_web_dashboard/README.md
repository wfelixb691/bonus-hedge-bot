# 🌐 Cloud Web Dashboard Dual-MT5 Bonus Hedging

Dashboard web realtime untuk memantau status trading Master & Slave secara live dari browser HP dan Laptop tanpa perlu membuka VPS!

---

## 📱 Tampilan Dashboard:
* **Rate Kurs USD/IDR** berjalan realtime (17.745).
* **Bid / Ask** live spread Gold (XAUUSD).
* **Equity & Balance & Credit Bonus** (Master vs Slave).
* **Margin Call (MC) Price & Jarak Pips**.
* **Margin Level %**.
* **Detail Posisi Hedge** lengkap dengan konversi Rupiah per tiket dan total net per baris.

---

## 🚀 Cara Menjalankan (2 Pilihan Mudah):

### PILIHAN 1: Jalankan Lokal di VPS Anda Sendiri
1. Pastikan Node.js terinstall di VPS, atau jalankan via terminal di folder ini:
   ```bash
   node server.js
   ```
2. Buka browser: `http://IP_VPS_ANDA:3000`

---

### PILIHAN 2: Deploy Gratis ke Cloud (Vercel / Render / Railway) - SANGAT DIREKOMENDASIKAN ⭐
Website akan online 24 jam nonstop dengan domain HTTPS gratis!
1. Upload folder `cloud_web_dashboard` ke GitHub Anda.
2. Buka [Vercel.com](https://vercel.com) $\rightarrow$ Klik **Add New Project** $\rightarrow$ Pilih repo GitHub ini $\rightarrow$ Klik **Deploy**!
3. Anda akan langsung mendapatkan URL web gratis, contoh: `https://hedgemonitor-felix.vercel.app`.

---

## ⚙️ Cara Menghubungkan MT5 ke Web Dashboard Ini:

1. Di MT5 Master, tekan **`F7`** (Setting Input EA):
   * `InpEnableWebDashboard` = **`true`**
   * `InpWebDashboardUrl` = Masukkan URL web Anda + `/api/telemetry`
     *(Contoh: `https://hedgemonitor-felix.vercel.app/api/telemetry`)*
   * `InpWebIntervalSec` = **`2`** (Update setiap 2 detik)
2. Di MT5 Master menu **`Tools` $\rightarrow$ `Options` $\rightarrow$ Tab `Expert Advisors`**:
   * Centang **`Allow WebRequest for listed URL`**.
   * Tambahkan URL domain web Anda (contoh: `https://hedgemonitor-felix.vercel.app`).
3. Selesai! MT5 akan otomatis mengirim data realtime ke website, dan client Anda bisa memantau trading dari HP mereka masing-masing!
