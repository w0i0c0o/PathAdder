@echo off
REM ============================================================================
REM  PathAdder - install.bat
REM  Double-click entry: registers the .exe right-click menu (user level).
REM  No administrator privileges required.
REM  This file is intentionally kept pure ASCII so that cmd.exe can read it
REM  under any code page.
REM ============================================================================

powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0install.ps1"
echo.
echo Done. You can close this window.
pause
