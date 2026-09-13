@echo off
rem par-term + borderless drag helper
start "" "%~dp0par-term.exe"
start "" /min powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0par-term-drag.ps1"
