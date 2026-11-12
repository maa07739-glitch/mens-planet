@echo off
title MEN'S PLANET | Admin Portal Launcher
echo ========================================================
echo   MEN'S PLANET - Dedicated Admin Portal Launcher
echo ========================================================
set "HTML_PATH=%~dp0admin\index.html"

if exist "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" (
    start "" "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" --app="%HTML_PATH%" --window-size=1400,900
    exit
)

if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" (
    start "" "%ProgramFiles%\Google\Chrome\Application\chrome.exe" --app="%HTML_PATH%" --window-size=1400,900
    exit
)

start "" "%HTML_PATH%"
exit
