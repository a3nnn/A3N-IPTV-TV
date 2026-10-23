@echo off
cd /d "%~dp0"
title A3N IPTV Player - New release
echo.
set /p VER=Version number (example 1.0.1): 
if "%VER%"=="" goto :eof
git add -A
git commit -m "Release %VER%"
git pull --rebase origin main
git push origin main
git tag v%VER%
git push origin v%VER%
if errorlevel 1 goto :fail
echo.
echo  Done! GitHub is now building version %VER% (about 10 minutes).
echo  Watch it here: https://github.com/a3nnn/A3N-IPTV-TV/actions
start "" "https://github.com/a3nnn/A3N-IPTV-TV/actions"
pause
exit /b 0
:fail
echo.
echo  Failed. Take a screenshot and send it.
pause
exit /b 1
