@echo off
title HyperDrop Launcher
cd /d "%~dp0"
echo Starting HyperDrop Core Engine...
start "" "%~dp0node.exe" "%~dp0server\index.js"
timeout /t 2 /nobreak >nul
echo Opening HyperDrop in your default browser...
start http://127.0.0.1:3000
exit
