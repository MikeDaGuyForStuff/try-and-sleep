@echo off
rem Starts a Rojo server for all three Try and Sleep places at once.
rem Each place gets its own window and port. Close a window to stop syncing that place.
rem
rem Then in each Studio window: Plugins tab > Rojo > enter the port below > Connect.
rem   try and sleep (lobby)   port 34872
rem   chapter 1               port 34873
rem   chapter 2               port 34874

cd /d "%~dp0"

where rojo >nul 2>nul
if errorlevel 1 (
    echo Rojo isn't installed or isn't on your PATH.
    echo Run "rokit install" in this folder, then try again.
    pause
    exit /b 1
)

start "Rojo - try and sleep (lobby) - port 34872" cmd /k rojo serve default.project.json
start "Rojo - chapter 1 - port 34873" cmd /k rojo serve chapter-1.project.json
start "Rojo - chapter 2 - port 34874" cmd /k rojo serve chapter-2.project.json

echo.
echo Rojo is running for all three places:
echo   try and sleep (lobby)   port 34872
echo   chapter 1               port 34873
echo   chapter 2               port 34874
echo.
echo In each Studio window: Plugins tab ^> Rojo ^> type the port ^> Connect.
echo.
pause
