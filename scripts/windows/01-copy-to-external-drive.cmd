@echo off
REM ===========================================================================================
REM 01-copy-to-external-drive.cmd
REM
REM Run this FIRST, right after booting into WinRE Command Prompt, from wherever this folder
REM currently sits (normally a FAT32 USB flash drive — macOS can write to that directly but
REM cannot write to the external hard drive's NTFS filesystem; see docs/diagrams/file-transfer-relay.md
REM in the main repo for why).
REM
REM Copies this whole folder onto the external hard drive, so 02-capture-ffu.cmd and
REM 03-apply-ffu.cmd can be run from there. Never guesses the destination drive letter — lists
REM volumes and asks you to confirm one. Safe to re-run (uses robocopy, which resyncs rather than
REM erroring on a partial previous copy).
REM ===========================================================================================

setlocal enabledelayedexpansion

set "SRCDIR=%~dp0"
if "%SRCDIR:~-1%"=="\" set "SRCDIR=%SRCDIR:~0,-1%"
for %%I in ("%SRCDIR%") do set "FOLDERNAME=%%~nxI"
set "SRCDRIVE=%~d0"

echo ===========================================================================================
echo  01-copy-to-external-drive.cmd
echo  Copies "%FOLDERNAME%" from %SRCDRIVE% (its current location) onto the external hard drive.
echo ===========================================================================================
echo.

echo === Step 1: Checking the source folder is intact ===
if not exist "%SRCDIR%\02-capture-ffu.cmd" (
    echo ERROR: 02-capture-ffu.cmd not found in %SRCDIR%.
    echo This does not look like a complete copy of the %FOLDERNAME% folder - refusing to copy an
    echo incomplete source. Stopping.
    goto :end
)
echo Source OK: %SRCDIR%

echo.
echo === Step 2: Listing volumes to identify the external hard drive ===
(
echo list volume
echo exit
) > "%TEMP%\dp_listvol_copyext.txt"
diskpart /s "%TEMP%\dp_listvol_copyext.txt"
echo.
echo Identify the EXTERNAL HARD DRIVE above - do NOT type %SRCDRIVE% (this script's own source
echo drive); that would copy the folder onto itself.
set /p DESTLETTER="Type the destination drive letter (external hard drive), no colon: "
set "DESTDRIVE=%DESTLETTER%:"

if /I "%DESTDRIVE%"=="%SRCDRIVE%" (
    echo ERROR: destination drive is the same as the source drive. Refusing to copy onto itself.
    goto :end
)
if not exist "%DESTDRIVE%\" (
    echo ERROR: drive %DESTDRIVE% does not appear to exist. Check the letter and try again.
    goto :end
)

set "DESTDIR=%DESTDRIVE%\%FOLDERNAME%"

if exist "%DESTDIR%\" (
    echo.
    echo NOTE: %DESTDIR% already exists - this looks like a re-run. Only new or changed files will
    echo be copied.
)

echo.
echo About to copy:
echo   FROM: %SRCDIR%
echo   TO:   %DESTDIR%
set /p CONFIRM="Type YES to proceed: "
if /I not "%CONFIRM%"=="YES" (
    echo Cancelled by user. Nothing copied.
    goto :end
)

echo.
echo === Step 3: Copying ===
set "LOG=%DESTDRIVE%\01-copy-to-external-drive-log.txt"
robocopy "%SRCDIR%" "%DESTDIR%" /E /R:3 /W:5 /LOG:"%LOG%" /TEE
set "RC=%ERRORLEVEL%"

if %RC% GEQ 8 (
    echo.
    echo ERROR: robocopy reported a failure ^(exit code %RC%^). See %LOG% for detail.
    goto :end
)

if not exist "%DESTDIR%\02-capture-ffu.cmd" (
    echo.
    echo ERROR: 02-capture-ffu.cmd not found at the destination after copying. Something went
    echo wrong - check %LOG%.
    goto :end
)

echo.
echo Done. Robocopy exit code %RC% (0-7 is normal).
echo.
echo Next: on this same drive, run:
echo   %DESTDRIVE%
echo   cd \%FOLDERNAME%
echo   02-capture-ffu.cmd
echo.
echo Log of this copy: %LOG%

:end
endlocal
