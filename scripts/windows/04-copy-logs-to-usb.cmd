@echo off
REM ===========================================================================================
REM 04-copy-logs-to-usb.cmd
REM
REM Run last, after 02-capture-ffu.cmd and/or 03-apply-ffu.cmd, from the external hard drive.
REM Copies the logs they produced back onto a FAT32 USB flash drive, so they can be brought to
REM the Mac and read there directly (macOS can read FAT32 natively; it cannot write to the
REM external hard drive's NTFS filesystem — see docs/diagrams/file-transfer-relay.md in the main
REM repo for why this hop exists at all).
REM
REM Refuses to run if there's no evidence either script actually ran from this drive. Never
REM guesses the destination drive letter. Safe to re-run (robocopy resyncs rather than erroring
REM on files already copied back from an earlier pass).
REM ===========================================================================================

setlocal enabledelayedexpansion

set "SRCDRIVE=%~d0"
set "LOGROOT=%SRCDRIVE%\capture-logs"

echo ===========================================================================================
echo  04-copy-logs-to-usb.cmd
echo  Copies %LOGROOT% from this drive (%SRCDRIVE%) onto a USB flash drive.
echo ===========================================================================================
echo.

echo === Step 1: Checking there is something to copy ===
if not exist "%LOGROOT%\" (
    echo ERROR: %LOGROOT% does not exist.
    echo This means neither 02-capture-ffu.cmd nor 03-apply-ffu.cmd has produced logs on
    echo %SRCDRIVE% yet - nothing to copy. Stopping.
    goto :end
)

set "FOUNDLOG=0"
for /f "delims=" %%D in ('dir /b /ad "%LOGROOT%" 2^>nul') do (
    if exist "%LOGROOT%\%%D\02-capture-ffu.log" set "FOUNDLOG=1"
    if exist "%LOGROOT%\%%D\03-apply-ffu.log" set "FOUNDLOG=1"
)
if "%FOUNDLOG%"=="0" (
    echo ERROR: no folder under %LOGROOT% contains a recognizable log file.
    echo This does not look like a genuine run. Stopping - refusing to guess.
    goto :end
)
echo Source OK.

echo.
echo === Step 2: Listing volumes to identify the USB flash drive ===
(
echo list volume
echo exit
) > "%TEMP%\dp_listvol_copylogs.txt"
diskpart /s "%TEMP%\dp_listvol_copylogs.txt"
echo.
echo Identify the USB FLASH DRIVE (boot media) above - do NOT type %SRCDRIVE% (this script's own
echo source drive, the external hard drive holding the logs).
set /p DESTLETTER="Type the destination drive letter (USB flash drive), no colon: "
set "DESTDRIVE=%DESTLETTER%:"

if /I "%DESTDRIVE%"=="%SRCDRIVE%" (
    echo ERROR: destination drive is the same as the source drive. Refusing to copy onto itself.
    goto :end
)
if not exist "%DESTDRIVE%\" (
    echo ERROR: drive %DESTDRIVE% does not appear to exist. Check the letter and try again.
    goto :end
)

set "DESTDIR=%DESTDRIVE%\capture-logs"

echo.
echo About to copy:
echo   FROM: %LOGROOT%
echo   TO:   %DESTDIR%
set /p CONFIRM="Type YES to proceed: "
if /I not "%CONFIRM%"=="YES" (
    echo Cancelled by user. Nothing copied.
    goto :end
)

echo.
echo === Step 3: Copying ===
set "LOG=%DESTDRIVE%\copy-logs-to-usb-log.txt"
robocopy "%LOGROOT%" "%DESTDIR%" /E /R:3 /W:5 /LOG:"%LOG%" /TEE
set "RC=%ERRORLEVEL%"

if %RC% GEQ 8 (
    echo.
    echo ERROR: robocopy reported a failure ^(exit code %RC%^). See %LOG% for detail.
    goto :end
)

echo.
echo Done. Robocopy exit code %RC% (0-7 is normal). Bring the USB flash drive back to the Mac -
echo the logs are under: %DESTDIR%

:end
endlocal
