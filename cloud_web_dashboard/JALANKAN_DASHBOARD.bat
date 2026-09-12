@echo off
title DUAL-MT5 CLOUD WEB DASHBOARD 24/7 (v1.24)
color 0A

:: Pastikan selalu berjalan di folder lokasi file .bat ini
cd /d "%~dp0"

echo ================================================================
echo   DUAL-MT5 BONUS HEDGING BOT - CLOUD WEB DASHBOARD (v1.24)
echo ================================================================
echo.

:: Cek apakah Node.js sudah terinstall
where node >nul 2>nul
if %errorlevel% neq 0 (
    color 0C
    echo [ERROR] Node.js BELUM TERINSTALL di VPS ini!
    echo.
    echo Silakan download dan install Node.js v16.20.2 (Khusus Windows 2012):
    echo https://nodejs.org/dist/v16.20.2/node-v16.20.2-x64.msi
    echo.
    echo Setelah di-install, silakan jalankan kembali file ini.
    echo.
    pause
    exit /b
)

echo [OK] Node.js terdeteksi!
echo [*] Menjalankan Web Dashboard Server di Port 3000...
echo.
echo ----------------------------------------------------------------
echo   Link Akses Lokal di VPS : http://localhost:3000
echo   Link Telemetri MT5      : http://localhost:3000/api/telemetry
echo ----------------------------------------------------------------
echo.
echo Biarkan jendela ini tetap TERBUKA agar dashboard selalu online 24/7.
echo.

:LOOP
node server.js
echo.
echo [PERINGATAN] Server terhenti.
echo Mengulang kembali secara otomatis dalam 3 detik...
timeout /t 3 >nul
goto LOOP
