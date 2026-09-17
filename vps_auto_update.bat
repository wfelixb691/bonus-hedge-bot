@echo off
setlocal enabledelayedexpansion
title DUAL-MT5 BONUS HEDGE BOT AUTO-UPDATER v1.27
cd /d "%~dp0"

echo ================================================================
echo   AUTO-UPDATER ^& MEMORY FLUSHER - BONUS HEDGE BOT MT5 v1.27
echo ================================================================
echo.

:: 1. Tarik update terbaru dari Git (jika repo git aktif)
where git >nul 2>nul
if %errorlevel% equ 0 (
    if exist ".git" (
        echo [1/5] Mengambil update terbaru dari GitHub repo...
        git pull origin main
    )
) else (
    echo [1/5] Git tidak terdeteksi, menggunakan file lokal di folder ini...
)
echo.

:: 2. Cari metaeditor64.exe untuk Auto-Compile ke .ex5
echo [2/5] Mendeteksi MetaEditor untuk kompilasi otomatis...
set "COMPILER="
if exist "C:\Program Files\Prime Codex MetaTrader 5\metaeditor64.exe" set "COMPILER=C:\Program Files\Prime Codex MetaTrader 5\metaeditor64.exe"
if exist "C:\Program Files\Prime Codex MetaTrader 5 TB 1\metaeditor64.exe" set "COMPILER=C:\Program Files\Prime Codex MetaTrader 5 TB 1\metaeditor64.exe"
if exist "C:\Program Files\Prime Codex MetaTrader 5 TB 2\metaeditor64.exe" set "COMPILER=C:\Program Files\Prime Codex MetaTrader 5 TB 2\metaeditor64.exe"
if exist "C:\Program Files\Prime Codex MetaTrader 5 Felix-1 Terminal\metaeditor64.exe" set "COMPILER=C:\Program Files\Prime Codex MetaTrader 5 Felix-1 Terminal\metaeditor64.exe"
if exist "C:\Program Files\Prime Codex MetaTrader 5 Felix-2 Terminal\metaeditor64.exe" set "COMPILER=C:\Program Files\Prime Codex MetaTrader 5 Felix-2 Terminal\metaeditor64.exe"
if exist "C:\Program Files\MetaTrader 5\metaeditor64.exe" set "COMPILER=C:\Program Files\MetaTrader 5\metaeditor64.exe"

if "%COMPILER%"=="" (
    for /r "C:\Program Files" %%F in (metaeditor64.exe) do (
        if exist "%%F" (
            set "COMPILER=%%F"
            goto :found_comp
        )
    )
)

:found_comp
if not "%COMPILER%"=="" (
    echo [OK] Compiler ditemukan: "%COMPILER%"
    echo [*] Meng-compile BonusHedge_Master.mq5...
    "%COMPILER%" /compile:"%~dp0BonusHedge_Master.mq5" /log:"%~dp0compile_master.log"
    echo [*] Meng-compile BonusHedge_Slave.mq5...
    "%COMPILER%" /compile:"%~dp0BonusHedge_Slave.mq5" /log:"%~dp0compile_slave.log"
) else (
    echo [!] MetaEditor tidak ditemukan di lokasi standar, menggunakan file .ex5 yang sudah ada.
)
echo.

:: 3. Cari folder MT5 Experts & Presets di VPS lalu sebarkan file
echo [3/5] Mendeteksi dan menyalin file ke seluruh folder terminal MT5...
set "TARGET_DIR=%APPDATA%\MetaQuotes\Terminal"
set "COPIED=0"

if exist "!TARGET_DIR!" (
    for /d %%T in ("!TARGET_DIR!\*") do (
        if exist "%%T\MQL5\Experts" (
            echo [+] Mengupdate Terminal: %%~nxT
            copy /Y "%~dp0BonusHedge_Master.mq5" "%%T\MQL5\Experts\" >nul 2>nul
            copy /Y "%~dp0BonusHedge_Master.ex5" "%%T\MQL5\Experts\" >nul 2>nul
            copy /Y "%~dp0BonusHedge_Slave.mq5" "%%T\MQL5\Experts\" >nul 2>nul
            copy /Y "%~dp0BonusHedge_Slave.ex5" "%%T\MQL5\Experts\" >nul 2>nul
            
            if not exist "%%T\MQL5\Presets" mkdir "%%T\MQL5\Presets"
            copy /Y "%~dp0Pair1_Master1.set" "%%T\MQL5\Presets\" >nul 2>nul
            copy /Y "%~dp0Pair1_Slave2.set" "%%T\MQL5\Presets\" >nul 2>nul
            copy /Y "%~dp0Pair2_Master3.set" "%%T\MQL5\Presets\" >nul 2>nul
            copy /Y "%~dp0Pair2_Slave4.set" "%%T\MQL5\Presets\" >nul 2>nul
            set /a COPIED+=1
        )
    )
)

:: Cek juga jika ada instalasi portable di C:\Program Files
for /d %%P in ("C:\Program Files\*MetaTrader*") do (
    if exist "%%P\MQL5\Experts" (
        echo [+] Mengupdate Portable Terminal: %%~nxP
        copy /Y "%~dp0BonusHedge_Master.mq5" "%%P\MQL5\Experts\" >nul 2>nul
        copy /Y "%~dp0BonusHedge_Master.ex5" "%%P\MQL5\Experts\" >nul 2>nul
        copy /Y "%~dp0BonusHedge_Slave.mq5" "%%P\MQL5\Experts\" >nul 2>nul
        copy /Y "%~dp0BonusHedge_Slave.ex5" "%%P\MQL5\Experts\" >nul 2>nul
        if not exist "%%P\MQL5\Presets" mkdir "%%P\MQL5\Presets"
        copy /Y "%~dp0Pair1_Master1.set" "%%P\MQL5\Presets\" >nul 2>nul
        copy /Y "%~dp0Pair1_Slave2.set" "%%P\MQL5\Presets\" >nul 2>nul
        copy /Y "%~dp0Pair2_Master3.set" "%%P\MQL5\Presets\" >nul 2>nul
        copy /Y "%~dp0Pair2_Slave4.set" "%%P\MQL5\Presets\" >nul 2>nul
        set /a COPIED+=1
    )
)

echo.
echo [4/5] Berhasil mendistribusikan file ke !COPIED! terminal MT5!
echo.

:: 4. FLUSH MEMORY & RESTART TERMINAL (AGAR KODE BARU LANGSUNG AKTIF DI RAM)
echo [5/5] FLUSH MEMORI MT5:
echo Agar memori terminal bersih dari state/timer lama, terminal MT5 perlu di-restart sekejap.
set /p RESTART_MT5="Restart semua terminal MT5 sekarang secara otomatis? (Y/N) [Default: Y]: "
if "%RESTART_MT5%"=="" set RESTART_MT5=Y
if /i "%RESTART_MT5%"=="Y" (
    echo.
    echo [*] Mendata path terminal yang sedang berjalan dan me-restart...
    powershell -NoProfile -Command "$paths = Get-Process terminal64 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path -Unique; if($paths) { Stop-Process -Name terminal64 -Force; Start-Sleep -Seconds 3; foreach($p in $paths) { Start-Process $p }; Write-Host '>>> [BERHASIL] Semua terminal MT5 telah direstart dan memuat EA versi 1.27 ke RAM!' -ForegroundColor Green } else { Write-Host '[INFO] Tidak ada terminal64.exe yang sedang berjalan.' -ForegroundColor Yellow }"
) else (
    echo.
    echo [!] Anda memilih TIDAK me-restart MT5 otomatis.
    echo     Silakan restart MT5 atau ganti timeframe di chart agar EA reload ke RAM.
)

echo.
echo ================================================================
echo   UPDATE v1.27 SELESAI DENGAN SUKSES!
echo ================================================================
pause
