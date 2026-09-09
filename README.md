# ⚡ All-in-One Dual-MT5 Grid & Bonus Hedging Bot

Bot trading otonom all-in-one yang mengintegrasikan strategi **Grid Trading di Akun Master (STP)** dan **Reverse Hedging di Akun Bonus (20% LP)** secara simultan dengan **1-Click Auto-Detection (Zero Questions Asked)**.

---

## 🌟 1-Click Launch (Tanpa Perlu Ketik Path / Server / Login)

Karena Anda sudah login di aplikasi **MT5 Master** dan **MT5 Slave** di VPS:
1. Jalankan bot:
   ```cmd
   python main.py
   ```
2. Tekan **`1` (atau langsung tekan Enter)**.
3. Bot akan **OTOMATIS**:
   - Menemukan lokasi folder MT5 Master dan MT5 Slave di VPS.
   - Membaca nomor login & server yang sedang aktif di terminal.
   - Membaca saldo modal & menerapkan rasio lot (0.10 -> 0.11) dan target TP $31.74.
   - **Langsung mulai trading detik itu juga tanpa menanyakan pertanyaan apapun!**

---

## 📁 File Penting di Folder

- `main.py`: Entry point bot (1-Click Auto Launch)
- `terminal_scanner.py`: Scanner otomatis pendeteksi terminal MT5 di Windows
- `grid_engine.py`: Robot Grid otomatis di Akun Master
- `hedger_engine.py`: Robot Reverse Hedger di Akun Slave
- `mt5_connector.py`: Bridge simultan dual-terminal MT5
- `lot_calculator.py`: Kalkulasi pembesaran lot bonus
- `state_manager.py`: Manajemen relasi tiket pasangan
- `config.json`: Penyimpanan konfigurasi
