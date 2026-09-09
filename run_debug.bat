@echo off
title Debug Order Test - MT5
cd /d "%~dp0"
echo ============================================================
echo  DEBUG: Test koneksi MT5 dan buka order Gold
echo ============================================================
"C:\Users\Administrator\AppData\Local\Programs\Python\Python38\python.exe" debug_order.py
pause
