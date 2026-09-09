@echo off
title Live Dashboard - Dual MT5 Bonus Hedging
cd /d "%~dp0"

echo ============================================================
echo   STARTING LIVE VISUAL WEB DASHBOARD...
echo ============================================================
echo.

"C:\Users\Administrator\AppData\Local\Programs\Python\Python38\python.exe" live_dashboard.py
if %ERRORLEVEL% NEQ 0 (
    python live_dashboard.py
)
pause
