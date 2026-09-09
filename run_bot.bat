@echo off
title All-in-One Dual-MT5 Bonus Hedging Bot
cd /d "%~dp0"
echo ============================================================
echo  ⚡ ALL-IN-ONE DUAL-MT5 BONUS HEDGING BOT
echo ============================================================
echo Menjalankan bot...

if exist "C:\Users\Administrator\AppData\Local\Programs\Python\Python38\python.exe" (
    "C:\Users\Administrator\AppData\Local\Programs\Python\Python38\python.exe" main.py
) else (
    python main.py
)

pause
