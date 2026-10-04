@echo off
REM ============================================================================
REM  PathAdder - uninstall.bat
REM  Double-click entry: removes the .exe right-click menu (user level).
REM  No administrator privileges required.
REM  Backups and logs under %LOCALAPPDATA%\PathAdder are kept on purpose.
REM  This file is intentionally kept pure ASCII so that cmd.exe can read it
REM  under any code page.
REM ============================================================================

powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"
echo.
echo Done. You can close this window.
pause
