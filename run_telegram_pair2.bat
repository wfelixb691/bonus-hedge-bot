@echo off
title Dual-MT5 Bonus Hedging - Smart Telegram Live Reporter [PAIR 2]
color 0B
cls
echo ======================================================================
echo    DUAL-MT5 BONUS HEDGING BOT - TELEGRAM LIVE REPORTER [PAIR 2]
echo ======================================================================
echo.

set PATH=C:\Users\Administrator\AppData\Local\Programs\Python\Python312;C:\Users\Administrator\AppData\Local\Programs\Python\Python312\Scripts;%LOCALAPPDATA%\Programs\Python\Python312;%LOCALAPPDATA%\Programs\Python\Python312\Scripts;%PATH%

if exist "C:\Users\Administrator\AppData\Local\Programs\Python\Python312\python.exe" (
    "C:\Users\Administrator\AppData\Local\Programs\Python\Python312\python.exe" telegram_reporter2.py
) else if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" (
    "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" telegram_reporter2.py
) else (
    python telegram_reporter2.py
)

pause
