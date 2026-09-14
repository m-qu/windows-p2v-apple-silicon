@echo off
REM ===========================================================================================
REM 02-capture-ffu.cmd
REM
REM Run from the WinRE/Setup Command Prompt (Troubleshoot -> Advanced options -> Command Prompt),
REM from this folder's copy on the external hard drive (after 01-copy-to-external-drive.cmd).
REM
REM Captures an OFFLINE image of the physical disk with DISM /Capture-FFU — Windows is not
REM running, so nothing can be mid-write the way a live VSS-based capture can be. This is the
REM entire reason this approach works where a live capture doesn't; see
REM docs/01-problem-and-root-cause.md in the main repo.
REM
REM Pauses before the one step that reads the whole physical disk and requires you to type the
REM disk number you actually confirmed from diskpart's own listing. Never guesses.
REM ===========================================================================================

setlocal enabledelayedexpansion

set "DRIVE=%~d0"
if exist "%~dp0config.cmd" (call "%~dp0config.cmd") else (
    set "DEVICE_NAME=my-laptop"
    set "FFU_NAME=my-laptop.ffu"
)

set "LOGROOT=%DRIVE%\capture-logs"
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value ^| find "="') do set "DT=%%I"
set "STAMP=%DT:~0,8%-%DT:~8,6%"
set "LOGDIR=%LOGROOT%\%STAMP%"
mkdir "%LOGDIR%" 2>nul
set "LOG=%LOGDIR%\02-capture-ffu.log"

echo === 02-capture-ffu started %DATE% %TIME% === > "%LOG%"

echo.
echo === Step 1: Checking DISM supports /Capture-FFU ===
dism /Capture-FFU /? > "%LOGDIR%\dism-check.txt" 2>&1
type "%LOGDIR%\dism-check.txt"
type "%LOGDIR%\dism-check.txt" >> "%LOG%"
echo.
echo If you saw usage help above (not an "unknown option" error), DISM supports Capture-FFU.
set /p CHECK1="Type YES if the help text looked correct, anything else to stop: "
if /I not "%CHECK1%"=="YES" (
    echo Cancelled by user at Step 1. >> "%LOG%"
    echo Cancelled. Log: %LOG%
    goto :end
)

echo.
echo === Step 2: Listing disks - identify the SOURCE disk (the physical Windows disk) ===
(
echo list disk
echo exit
) > "%TEMP%\dp_listdisk.txt"
diskpart /s "%TEMP%\dp_listdisk.txt" > "%LOGDIR%\diskpart-listdisk.txt" 2>&1
type "%LOGDIR%\diskpart-listdisk.txt"
type "%LOGDIR%\diskpart-listdisk.txt" >> "%LOG%"

echo.
set /p SRCDISK="Type the SOURCE disk number (the physical Windows disk you confirmed above): "

set "FFUFILE=%DRIVE%\%FFU_NAME%"
if exist "%FFUFILE%" (
    echo.
    echo WARNING: %FFUFILE% already exists. Continuing will overwrite it.
    set /p OVERWRITE="Type OVERWRITE-EXISTING-FFU to proceed anyway, anything else to stop: "
    if /I not "!OVERWRITE!"=="OVERWRITE-EXISTING-FFU" (
        echo Cancelled by user - existing FFU not overwritten. >> "%LOG%"
        echo Cancelled. Log: %LOG%
        goto :end
    )
)

echo.
echo === Step 3: Capturing ===
echo About to run:
echo   dism /Capture-FFU /ImageFile:%FFUFILE% /CaptureDrive:\\.\PhysicalDrive%SRCDISK% /Name:"%DEVICE_NAME%" /Compress:Default
echo.
echo This reads the ENTIRE physical disk %SRCDISK% and can take 30-90+ minutes. Let it finish
echo completely once started.
set /p CONFIRM="Type YES (all caps) to proceed: "
if /I not "%CONFIRM%"=="YES" (
    echo Cancelled by user before capture. >> "%LOG%"
    echo Cancelled. Log: %LOG%
    goto :end
)

echo.
echo Running now - DISM's own live percentage progress stays visible below.
echo === Step 3: Capture started %DATE% %TIME% (see dism-capture-detail.log for DISM's own log) === >> "%LOG%"
dism /Capture-FFU /ImageFile:%FFUFILE% /CaptureDrive:\\.\PhysicalDrive%SRCDISK% /Name:"%DEVICE_NAME%" /Compress:Default /LogPath:"%LOGDIR%\dism-capture-detail.log"
set "CAPRC=%ERRORLEVEL%"
echo === Step 3: Capture exited with code %CAPRC% === >> "%LOG%"

if not "%CAPRC%"=="0" (
    echo.
    echo ERROR: Capture-FFU exited with code %CAPRC%. See %LOGDIR%\dism-capture-detail.log for detail.
    goto :end
)
if not exist "%FFUFILE%" (
    echo ERROR: capture did not produce %FFUFILE% despite exit code 0. Check the log above.
    goto :end
)

echo.
echo Done. Captured: %FFUFILE%
for %%F in ("%FFUFILE%") do echo Size: %%~zF bytes
echo Log: %LOG%
echo.
echo Next: run 03-apply-ffu.cmd from this same folder.

:end
endlocal
