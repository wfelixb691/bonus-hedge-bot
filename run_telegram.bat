@echo off
title Dual-MT5 Bonus Hedging - Smart Telegram Live Reporter
color 0A
cls
echo ======================================================================
echo    DUAL-MT5 BONUS HEDGING BOT - SMART TELEGRAM LIVE REPORTER
echo ======================================================================
echo.

set PATH=C:\Users\Administrator\AppData\Local\Programs\Python\Python312;C:\Users\Administrator\AppData\Local\Programs\Python\Python312\Scripts;%LOCALAPPDATA%\Programs\Python\Python312;%LOCALAPPDATA%\Programs\Python\Python312\Scripts;%PATH%

if exist "C:\Users\Administrator\AppData\Local\Programs\Python\Python312\python.exe" (
    "C:\Users\Administrator\AppData\Local\Programs\Python\Python312\python.exe" telegram_reporter.py
) else if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" (
    "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" telegram_reporter.py
) else (
    python telegram_reporter.py
)

pause
