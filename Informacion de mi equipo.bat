@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul
title Ism - Juntos Somos +

:: Obtención de datos del sistema
for /f "tokens=2 delims==" %%A in ('wmic computersystem get model /value') do set "MODELO=%%A"
for /f "tokens=2 delims==" %%A in ('wmic bios get serialnumber /value') do set "SERIAL=%%A"
for /f "tokens=2 delims=={}," %%A in ('wmic nicconfig where IPEnabled^=TRUE get IPAddress /value') do set "IP=%%A"
for /f "tokens=2 delims==" %%A in ('wmic nicconfig where IPEnabled^=TRUE get MACAddress /value') do set "MAC=%%A"

cls

echo.
echo                   JUNTOS SOMOS +
echo   --------------------------------------------------
echo.
echo   EQUIPO
echo      Nombre de Host   :  %COMPUTERNAME%
echo      Usuario          :  %USERNAME%
echo.
echo   HARDWARE
echo      Modelo           :  !MODELO!
echo      Serie            :  !SERIAL!
echo.
echo   CONECTIVIDAD
echo      Direccion IP     :  !IP!
echo      Direccion MAC    :  !MAC!
echo.
echo   --------------------------------------------------
echo       Fecha: %DATE% - %TIME:~0,5%
echo.
echo.
echo   Pulse cualquier tecla para cerrar la ventana. . .
pause >nul