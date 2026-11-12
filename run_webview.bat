@echo off
title MEN'S PLANET | Dedicated WebView App
echo ========================================================
echo   MEN'S PLANET - Dedicated Desktop WebView Launcher
echo ========================================================
echo Launching application in standalone WebView mode...

set "HTML_PATH=%~dp0index.html"

:: Check for Microsoft Edge WebView/App Mode
if exist "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" (
    start "" "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" --app="%HTML_PATH%" --window-size=1280,850
    goto end
)

:: Check for Google Chrome App Mode
if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" (
    start "" "%ProgramFiles%\Google\Chrome\Application\chrome.exe" --app="%HTML_PATH%" --window-size=1280,850
    goto end
)

if exist "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" (
    start "" "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" --app="%HTML_PATH%" --window-size=1280,850
    goto end
)

:: Default Browser fallback
start "" "%HTML_PATH%"

:end
echo Application launched!
exit
