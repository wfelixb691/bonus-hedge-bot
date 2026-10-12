@echo off
setlocal enabledelayedexpansion
title DUAL-MT5 BONUS HEDGE BOT AUTO-UPDATER v1.35 (MULTIPLIER 1.10)
cd /d "%~dp0"

echo ================================================================
echo   AUTO-UPDATER ^& MEMORY FLUSHER - BONUS HEDGE BOT MT5 v1.35
echo ================================================================
echo.

:: 1. Tarik update terbaru dari Git (Force Sync agar tidak gagal karena konflik .ex5 lokal)
where git >nul 2>nul
if %errorlevel% equ 0 (
    if exist ".git" (
        echo [1/5] Mengambil update terbaru dari GitHub repo...
        git fetch origin main
        git reset --hard origin/main
    )
) else (
    echo [1/5] Git tidak terdeteksi, menggunakan file lokal di folder ini...
)
echo.

:: 2. Cari metaeditor64.exe secara dinamis dari proses terminal MT5 yang sedang aktif
echo [2/5] Mendeteksi MetaEditor untuk kompilasi otomatis...
set "COMPILER="

:: A. Cek dari proses terminal64.exe yang sedang berjalan (100% Akurat)
for /f "usebackq delims=" %%E in (`powershell -NoProfile -Command "$p = Get-Process terminal64 -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Path; if($p) { $d = Split-Path $p; $ed = Join-Path $d 'metaeditor64.exe'; if(Test-Path $ed) { $ed } }"`) do (
    if exist "%%E" set "COMPILER=%%E"
)

:: B. Fallback lokasi standar jika terminal belum menyala
if "%COMPILER%"=="" (
    if exist "C:\Program Files\Prime Codex MetaTrader 5\metaeditor64.exe" set "COMPILER=C:\Program Files\Prime Codex MetaTrader 5\metaeditor64.exe"
    if exist "C:\Program Files\Prime Codex MetaTrader 5 TB 1\metaeditor64.exe" set "COMPILER=C:\Program Files\Prime Codex MetaTrader 5 TB 1\metaeditor64.exe"
    if exist "C:\Program Files\Prime Codex MetaTrader 5 TB 2\metaeditor64.exe" set "COMPILER=C:\Program Files\Prime Codex MetaTrader 5 TB 2\metaeditor64.exe"
    if exist "C:\Program Files\Prime Codex MetaTrader 5 Felix-1 Terminal\metaeditor64.exe" set "COMPILER=C:\Program Files\Prime Codex MetaTrader 5 Felix-1 Terminal\metaeditor64.exe"
    if exist "C:\Program Files\Prime Codex MetaTrader 5 Felix-2 Terminal\metaeditor64.exe" set "COMPILER=C:\Program Files\Prime Codex MetaTrader 5 Felix-2 Terminal\metaeditor64.exe"
    if exist "C:\Program Files\MetaTrader 5\metaeditor64.exe" set "COMPILER=C:\Program Files\MetaTrader 5\metaeditor64.exe"
)

:: C. Scan seluruh drive C jika masih belum ketemu
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
    for %%M in (BonusHedge_Master BonusHedge_Master_Pair1 BonusHedge_Master_Pair2 BonusHedge_Slave BonusHedge_Slave_Pair1 BonusHedge_Slave_Pair2) do (
        if exist "%~dp0%%M.mq5" (
            echo [*] Meng-compile %%M.mq5...
            "%COMPILER%" /compile:"%~dp0%%M.mq5" /log:"%~dp0compile_%%M.log"
        )
    )
) else (
    echo [!] MetaEditor tidak ditemukan, menggunakan pre-compiled .ex5 dari GitHub.
)
echo.

:: 3. Cari folder MT5 Experts & Presets di VPS lalu sebarkan file
echo [3/5] Mendeteksi dan menyalin file ke seluruh folder terminal MT5...
set "TARGET_DIR=%APPDATA%\MetaQuotes\Terminal"
set "COPIED=0"

if exist "!TARGET_DIR!\Common\Files" (
    del /F /Q "!TARGET_DIR!\Common\Files\bonus_slave_cfg*.dat" >nul 2>nul
)

if exist "!TARGET_DIR!" (
    for /d %%T in ("!TARGET_DIR!\*") do (
        if exist "%%T\MQL5\Experts" (
            echo [+] Mengupdate Terminal: %%~nxT
            copy /Y "%~dp0BonusHedge_Master*.mq5" "%%T\MQL5\Experts\" >nul 2>nul
            copy /Y "%~dp0BonusHedge_Master*.ex5" "%%T\MQL5\Experts\" >nul 2>nul
            copy /Y "%~dp0BonusHedge_Slave*.mq5" "%%T\MQL5\Experts\" >nul 2>nul
            copy /Y "%~dp0BonusHedge_Slave*.ex5" "%%T\MQL5\Experts\" >nul 2>nul
            
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
for /d %%P in ("C:\Program Files\*MetaTrader*" "C:\Program Files\Prime Codex*") do (
    if exist "%%P\MQL5\Experts" (
        echo [+] Mengupdate Portable Terminal: %%~nxP
        copy /Y "%~dp0BonusHedge_Master*.mq5" "%%P\MQL5\Experts\" >nul 2>nul
        copy /Y "%~dp0BonusHedge_Master*.ex5" "%%P\MQL5\Experts\" >nul 2>nul
        copy /Y "%~dp0BonusHedge_Slave*.mq5" "%%P\MQL5\Experts\" >nul 2>nul
        copy /Y "%~dp0BonusHedge_Slave*.ex5" "%%P\MQL5\Experts\" >nul 2>nul
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

:: 4. FLUSH MEMORY, UPDATE CHART PROFILE CACHE (.chr) 1.15 -> 1.10 & RESTART TERMINAL
echo [5/5] FLUSH MEMORI MT5 ^& MIGRASI CACHE CHART (1.15 -^> 1.10):
echo Me-restart semua terminal MT5 secara otomatis agar memori RAM 100%% bersih...
powershell -NoProfile -Command "$paths = Get-Process terminal64 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path -Unique; if($paths) { Stop-Process -Name terminal64 -Force; Start-Sleep -Seconds 3 }; $common = \"$env:APPDATA\MetaQuotes\Terminal\Common\Files\"; if(Test-Path $common) { Remove-Item -Path (Join-Path $common 'bonus_hedge_*.dat') -Force -ErrorAction SilentlyContinue; Remove-Item -Path (Join-Path $common 'bonus_cmd_*.dat') -Force -ErrorAction SilentlyContinue; Remove-Item -Path (Join-Path $common 'bonus_slave_cfg*.dat') -Force -ErrorAction SilentlyContinue }; $chrs = @(); if(Test-Path \"$env:APPDATA\MetaQuotes\Terminal\") { $chrs += Get-ChildItem -Path \"$env:APPDATA\MetaQuotes\Terminal\" -Filter '*.chr' -Recurse -ErrorAction SilentlyContinue }; $chrs += Get-ChildItem -Path 'C:\Program Files' -Filter '*.chr' -Recurse -ErrorAction SilentlyContinue; foreach($c in $chrs) { try { $raw = [System.IO.File]::ReadAllText($c.FullName); if($raw -match '1\.15') { $new = $raw -replace 'InpSlaveMultiplier=1\.15','InpSlaveMultiplier=1.10' -replace 'InpLotMultiplier=1\.15','InpLotMultiplier=1.10'; [System.IO.File]::WriteAllText($c.FullName, $new) } } catch {} }; if($paths) { foreach($p in $paths) { Start-Process $p; Start-Sleep -Seconds 2 }; Write-Host '>>> [BERHASIL] Semua terminal MT5 telah direstart dengan proteksi Cold-Start v1.35!' -ForegroundColor Green } else { Write-Host '[INFO] Cache chart telah di-upgrade ke 1.10. Silakan nyalakan terminal MT5.' -ForegroundColor Yellow }"

echo.
echo ================================================================
echo   UPDATE v1.35 (MULTIPLIER 1.10) SELESAI DENGAN SUKSES!
echo ================================================================
pause
