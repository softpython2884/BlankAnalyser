@echo off
rem ===========================================================================
rem  BlankAnalyser - lanceur unique
rem
rem  Double-clique ce fichier. C'est tout.
rem  Tu peux aussi glisser-deposer un .zip ou un .exe dessus : il sera
rem  directement mis en quarantaine et propose a l'analyse.
rem ===========================================================================
setlocal
chcp 65001 >nul 2>&1
title BlankAnalyser
cd /d "%~dp0"

if not exist "%~dp0Menu.ps1" (
  echo.
  echo   ERREUR : Menu.ps1 est introuvable a cote de ce fichier.
  echo   Garde BlankAnalyser.cmd dans le dossier du projet.
  echo.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Menu.ps1" -InitialTarget "%~1"
set RC=%ERRORLEVEL%

if not "%RC%"=="0" (
  echo.
  echo   Le menu s'est arrete sur une erreur ^(code %RC%^).
  echo.
  pause
)

endlocal
exit /b %RC%
