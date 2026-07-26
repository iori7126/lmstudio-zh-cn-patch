@echo off
setlocal
set "TARGET=%~1"

if not defined TARGET if exist "%LOCALAPPDATA%\Programs\LM Studio\resources\app\.webpack\renderer\main_window.js" set "TARGET=%LOCALAPPDATA%\Programs\LM Studio"
if not defined TARGET if exist "%LOCALAPPDATA%\LM Studio\resources\app\.webpack\renderer\main_window.js" set "TARGET=%LOCALAPPDATA%\LM Studio"
if not defined TARGET if exist "%ProgramFiles%\LM Studio\resources\app\.webpack\renderer\main_window.js" set "TARGET=%ProgramFiles%\LM Studio"

if not defined TARGET (
  echo Paste the folder that contains "LM Studio.exe", then press Enter.
  set /p "TARGET=LM Studio folder: "
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\invoke_patch_elevated.ps1" -TargetPath "%TARGET%" -Restore
if errorlevel 1 (
  echo Restore failed.
) else (
  echo Original file restored.
)
pause
