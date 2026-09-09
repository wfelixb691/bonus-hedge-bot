@echo off
title NovaHedge Global - Web Platform Server
color 0A
cd /d "%~dp0novahedge_global_platform"

echo =====================================================================
echo  ⚡ NOVAHEDGE GLOBAL — CLIENT, PERFORMANCE & NETWORK PLATFORM
echo =====================================================================
echo.
echo [INFO] Menjalankan Web Platform di port 4000...
echo [INFO] Buka browser di: http://localhost:4000
echo.

node server.js
if %errorlevel% neq 0 (
    echo [ERROR] Gagal menjalankan server Node.js. Pastikan Node.js terinstall.
    pause
)
