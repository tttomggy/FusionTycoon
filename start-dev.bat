@echo off
REM Double-click to start working on Fusion Tycoon: gets the latest code, then starts Rojo.
cd /d "%~dp0"
echo Getting the latest code...
git pull
echo.
echo Starting Rojo. In Studio: Plugins tab, Rojo, Connect. Keep this window open while you work.
rojo serve default.project.json
pause
