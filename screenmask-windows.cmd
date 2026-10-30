@echo off
rem webos-screenmask for Windows. Double-click for the menu, or run:
rem   screenmask-windows.cmd <tv-ip> install
rem   screenmask-windows.cmd <tv-ip> add bottom 20
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\screenmask.ps1" %*
rem Keep the window open after an error, so a double-click shows what happened.
if errorlevel 1 pause
