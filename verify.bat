@echo off
REM ============================================================================
REM  PathAdder - verify.bat
REM  Double-click entry: verifies the .exe right-click menu registration.
REM  No administrator privileges required.
REM  Checks registry structure, HKLM system verbs, third-party menu survival,
REM  and (when the environment allows) enumerates the real context menu via COM.
REM  This file is intentionally kept pure ASCII so that cmd.exe can read it
REM  under any code page.
REM ============================================================================

powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0verify-registration.ps1"
echo.
echo Exit code: %ERRORLEVEL%   (0 = pass, 1 = failures found, 2 = could not verify)
pause
