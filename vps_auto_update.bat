@echo off
setlocal enabledelayedexpansion
title DUAL-MT5 BONUS HEDGE BOT AUTO-UPDATER

echo ===================================================
echo   AUTO-UPDATER 30 VPS - BONUS HEDGE BOT MT5
echo ===================================================
echo.

:: 1. Tarik file .ex5 terbaru dari GitHub
echo [1/3] Mendownload file .ex5 terbaru dari GitHub repo...
git pull origin main

:: 2. Cari folder MT5 Experts di VPS
echo [2/3] Mendeteksi folder instalasi MT5 di VPS...
set "TARGET_DIR=%APPDATA%\MetaQuotes\Terminal"

if not exist "!TARGET_DIR!" (
    echo [WARNING] Folder roaming MT5 tidak ditemukan. Mencari instalasi MT5 lokal...
)

set "COPIED=0"
for /d %%T in ("!TARGET_DIR!\*") do (
    if exist "%%T\MQL5\Experts" (
        echo Menyalin file ke: %%T\MQL5\Experts
        copy /Y "BonusHedge_Master.ex5" "%%T\MQL5\Experts\" >nul
        copy /Y "BonusHedge_Slave.ex5" "%%T\MQL5\Experts\" >nul
        set /a COPIED+=1
    )
)

:: 3. Laporkan hasil
echo.
echo [3/3] Selesai! Berhasil mengupdate !COPIED! terminal MT5.
echo MT5 akan otomatis merefresh dan menjalankan EA versi terbaru!
echo.
pause
