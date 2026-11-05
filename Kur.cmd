@echo off
setlocal
where pwsh.exe >nul 2>nul
if errorlevel 1 (
  echo PowerShell 7 gerekiyor. Resmi kurulum bilgisi: https://aka.ms/powershell-release?tag=stable
  pause
  exit /b 1
)
pwsh.exe -NoProfile -File "%~dp0Kur.ps1" %*
set "result=%errorlevel%"
if not "%result%"=="0" pause
exit /b %result%
