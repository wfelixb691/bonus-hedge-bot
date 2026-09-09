@echo off
title Auto Compiler MQL5 - Bonus Hedge Bot
cd /d "%~dp0"

echo ============================================================
echo   1-CLICK AUTO COMPILER MQL5 (MASTER & SLAVE)
echo ============================================================
echo.

:: 1. Search for metaeditor64.exe on VPS
set "COMPILER="

if exist "C:\Program Files\Prime Codex MetaTrader 5\metaeditor64.exe" (
    set "COMPILER=C:\Program Files\Prime Codex MetaTrader 5\metaeditor64.exe"
) else if exist "C:\Program Files\Prime Codex MetaTrader 5 TB 1\metaeditor64.exe" (
    set "COMPILER=C:\Program Files\Prime Codex MetaTrader 5 TB 1\metaeditor64.exe"
) else if exist "C:\Program Files\Prime Codex MetaTrader 5 TB 2\metaeditor64.exe" (
    set "COMPILER=C:\Program Files\Prime Codex MetaTrader 5 TB 2\metaeditor64.exe"
) else if exist "C:\Program Files\Prime Codex MetaTrader 5 Felix-1 Terminal\metaeditor64.exe" (
    set "COMPILER=C:\Program Files\Prime Codex MetaTrader 5 Felix-1 Terminal\metaeditor64.exe"
) else if exist "C:\Program Files\Prime Codex MetaTrader 5 Felix-2 Terminal\metaeditor64.exe" (
    set "COMPILER=C:\Program Files\Prime Codex MetaTrader 5 Felix-2 Terminal\metaeditor64.exe"
) else if exist "C:\Program Files\MetaTrader 5\metaeditor64.exe" (
    set "COMPILER=C:\Program Files\MetaTrader 5\metaeditor64.exe"
)

if "%COMPILER%"=="" (
    echo [!] Mencari metaeditor64.exe di Program Files...
    for /r "C:\Program Files" %%F in (metaeditor64.exe) do (
        if exist "%%F" (
            set "COMPILER=%%F"
            goto :found_compiler
        )
    )
)

:found_compiler
if "%COMPILER%"=="" (
    echo [X] metaeditor64.exe tidak ditemukan di C:\Program Files.
    echo     Silakan buka MT5 di VPS, tekan F4, buka file .mq5 lalu tekan F7.
    goto :end
)

echo [OK] Compiler ditemukan: "%COMPILER%"
echo.

:: 2. Compile Master EA
echo [1/2] Meng-compile BonusHedge_Master.mq5...
"%COMPILER%" /compile:"%~dp0BonusHedge_Master.mq5" /log:"%~dp0compile_master.log"
if exist "%~dp0BonusHedge_Master.ex5" (
    echo       [BERHASIL] BonusHedge_Master.ex5 TERBENTUK!
) else (
    echo       [GAGAL] Lihat compile_master.log
    type "%~dp0compile_master.log"
)

echo.

:: 3. Compile Slave EA
echo [2/2] Meng-compile BonusHedge_Slave.mq5...
"%COMPILER%" /compile:"%~dp0BonusHedge_Slave.mq5" /log:"%~dp0compile_slave.log"
if exist "%~dp0BonusHedge_Slave.ex5" (
    echo       [BERHASIL] BonusHedge_Slave.ex5 TERBENTUK!
) else (
    echo       [GAGAL] Lihat compile_slave.log
    type "%~dp0compile_slave.log"
)

echo.
echo ============================================================
echo   SELESAI! File .ex5 sudah siap di folder ini.
echo   Silakan copy file .ex5 ke folder MQL5/Experts di MT5 Anda!
echo ============================================================

:end
pause
