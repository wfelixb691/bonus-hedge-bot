# 🚀 Panduan Deploy — NOVA HEDGE Global Platform ke Vercel

## 0. Prasyarat
- Akun Vercel (free tier cukup) + Vercel CLI: `npm i -g vercel` — atau cukup hubungkan repo GitHub.
- **Tidak ada `npm install`** — `server.js` murni Node stdlib (`http`, `fs`, `path`), zero dependencies.

## 1. Checklist kesiapan (sudah diverifikasi di kode)

| Item | Status |
|---|---|
| `server.js` export handler function (kontrak `@vercel/node`) | ✅ `module.exports = novaHedgeHandler` |
| `vercel.json` `includeFiles: "public/**"` agar static file ter-serve | ✅ |
| Sender VPS (`telegram_reporter.py`) kirim `master.login` | ✅ (wajib — sync ditolak 400 tanpa ini) |
| Heartbeat telemetry tiap 30s dari VPS | ✅ (dashboard menandai >15s sebagai offline) |
| Test suite: `node test_platform.js` → 26/26 PASS | ✅ |

**Temuan review yang sudah diperbaiki sebelum guide ini dibuat:**
1. ~~Sender tidak mengirim `master.login`~~ → dict telemetry Python sudah memuat `login`; ditambah guard `if not m.get("login"): return` agar tidak buang request.
2. ~~Kegagalan sync tertelan `except: pass`~~ → sekarang ada log `☁️ Web portal synced (HTTP 200)` / `⚠️ Web sync gagal: ...`.
3. ~~Dashboard flap OFFLINE~~ → heartbeat 30s ditambahkan ke loop utama kedua sender.

## 2. Deploy

### Opsi A — Vercel CLI (paling cepat)
```bash
cd novahedge_global_platform
vercel login
vercel --prod
```
Saat ditanya settings: framework **Other**, build command **kosong**, output dir **kosong**.

### Opsi B — GitHub
1. Push repo ke GitHub.
2. Vercel Dashboard → **Add New Project** → pilih repo.
3. **Root Directory**: `novahedge_global_platform` ← penting, jangan root repo!
4. Framework Preset: **Other**. Build & output settings: biarkan kosong.
5. Deploy.

## 3. Environment Variables (Vercel → Project → Settings → Environment Variables)

| Var | Wajib? | Nilai | Catatan |
|---|---|---|---|
| `PORT` | ❌ jangan diset | — | Vercel mengelola sendiri; kode fallback ke 4000 untuk lokal |

Platform ini **tidak butuh env var** untuk jalan (db in-memory, tanpa API key eksternal). Kalau nanti menambah secret (mis. token Telegram untuk notifikasi server-side), set di sini — jangan hardcode.

## 4. Konfigurasi sisi VPS (sender telemetry)

`telegram_reporter.py` dan `telegram_reporter2.py` default-nya sudah menunjuk ke:
```
https://novahedgeglobalplatform.vercel.app/api/mt5/sync
```
⚠️ **Ganti URL ini ke domain Vercel Anda yang sebenarnya** (hasil deploy langkah 2, mis. `novahedge-xxxx.vercel.app` atau custom domain), di fungsi `sync_to_cloud_portal(...)` kedua file.

BonusHedge_Master.mq5 (`InpWebDashboardUrl`, input EA) default `http://localhost:3000/api/telemetry` — ini jalur alternatif langsung dari EA. Server menerima `/api/telemetry` dan `/api/mt5/sync` sama-sama. Kalau dipakai, set di `.set` file ke `https://<domain-anda>/api/mt5/sync` dan tambahkan domain ke whitelist WebRequest MT5 (Tools → Options → Expert Advisors → Allow WebRequest).

## 5. Verifikasi pasca-deploy

```bash
# 1. Portal hidup (harus balikin HTML)
curl -s https://<domain-anda>/ | head -3

# 2. API live (harus balikin JSON standby, online:false)
curl -s https://<domain-anda>/api/mt5/live

# 3. Simulasi telemetry dari VPS (ganti login sesuai akun MT5 Anda)
curl -s -X POST https://<domain-anda>/api/mt5/sync \
  -H "Content-Type: application/json" \
  -d '{"master":{"login":100870,"balance":3000,"equity":3100,"profit":100},"slave":{"login":100871,"balance":3000,"equity":2900,"profit":-99}}'

# 4. Data harus muncul & online:true
curl -s "https://<domain-anda>/api/mt5/live?login=100870"
```
Lalu login ke portal (`admin / admin123`) dan cek dashboard live positions.

## 5b. WAJIB: Ganti password default setelah deploy

Login dengan `admin / admin123`, buka tab **Saya → 🔑 Ganti Password Login**, isi password saat ini (`admin123`) + password baru (min. 6 karakter), lalu submit. Sesi otomatis logout — login ulang dengan password baru.

Bisa juga via API:
```bash
curl -s -X POST https://<domain-anda>/api/auth/change-password \
  -H "Content-Type: application/json" \
  -d '{"userid":"admin","current_password":"admin123","new_password":"<password-baru-anda>"}'
```

Ulangi untuk user lain yang masih pakai `admin123` (seed data: `maharindra`, `hermawan`, `barry`, `yeoh`, `kevin`). Catatan: karena db in-memory, password yang diganti akan reset kembali ke seed saat lambda cold start — solusi permanen menunggu persistence layer (lihat batasan di bawah).

## 6. Batasan yang perlu diketahui (in-memory di serverless)

| Konsekuensi | Detail |
|---|---|
| **Data user reset saat cold start** | Registrasi/topup/perubahan fuel hilang jika lambda restart. Telemetry juga per-instance (sender & pembaca harus kena instance hangat — umumnya OK karena traffic hangat). |
| **Login bisa "logout" tiba-tiba** | Tidak ada session token; state login hanya di memori browser. |
| **Jangan dipakai untuk uang nyata dulu** | Deposit/withdraw masih simulasi client-side; komisi L2/L3 belum dihitung di cycle engine. |

👉 Perbaikan permanen = persistence (Vercel KV/Upstash Redis atau DB) + session token. Lihat "Langkah berikutnya".

## 7. Troubleshooting

| Gejala | Sebab → Solusi |
|---|---|
| `FUNCTION_INVOCATION_FAILED` / 500 di semua route | Export masih `http.Server` → pastikan `module.exports = novaHedgeHandler` (bukan `server`). |
| Halaman 404 semua | `public/**` tidak ter-include → cek `vercel.json` `includeFiles`, pastikan Root Directory benar. |
| Dashboard selalu "STANDBY" | Sender belum jalan / URL sync masih default localhost → cek log VPS, cek `curl` langkah 5.3. |
| Dashboard flap OFFLINE | Heartbeat tidak jalan (versi sender lama) → update ke versi yang ada `last_cloud_sync`. |
| Telemetry user A muncul di user B | Sudah diperbaiki (keyed per login). Pastikan frontend kirim `?login=` — terjadi otomatis setelah user bind MT5. |
| VPS tidak kirim apa-apa, tanpa error | Sekarang muncul `⚠️ Web sync gagal` di console VPS — lihat pesannya (DNS/SSL/403). |
