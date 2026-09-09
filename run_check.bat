@echo off
title Check MT5 Connection
cd /d "%~dp0"

if exist "C:\Users\Administrator\AppData\Local\Programs\Python\Python38\python.exe" (
    "C:\Users\Administrator\AppData\Local\Programs\Python\Python38\python.exe" check_mt5.py
) else (
    python check_mt5.py
)

pause
