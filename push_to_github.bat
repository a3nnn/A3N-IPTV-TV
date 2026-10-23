@echo off
cd /d "%~dp0"
title A3N IPTV Player - Upload to GitHub
echo.
echo  Uploading the project to https://github.com/a3nnn/A3N-IPTV-TV
echo  (a browser window may open to sign in to GitHub - that's normal)
echo.
if not exist ".git" (
  git init
  git branch -M main
  git remote add origin https://github.com/a3nnn/A3N-IPTV-TV.git
)
for /f "delims=" %%i in ('git config user.email') do set "HASMAIL=%%i"
if not defined HASMAIL (
  git config user.name "A3N"
  git config user.email "a3nnn@users.noreply.github.com"
)
git add -A
git commit -m "A3N IPTV Player source"
git push -u origin main --force
if errorlevel 1 goto :fail
echo.
echo  Done! Now run  release.bat  to build a release on GitHub.
pause
exit /b 0
:fail
echo.
echo  Upload failed. Take a screenshot and send it.
pause
exit /b 1
