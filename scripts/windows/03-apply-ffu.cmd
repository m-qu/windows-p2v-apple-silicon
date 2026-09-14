@echo off
REM ===========================================================================================
REM 03-apply-ffu.cmd
REM
REM Run after 02-capture-ffu.cmd, from the same folder on the external hard drive.
REM
REM Creates a fresh expandable VHDX, attaches it, applies the captured FFU onto it with
REM dism /Apply-FFU, then detaches it. Every destructive step requires a typed confirmation, and
REM the disk number used for Apply-FFU is always the one YOU identify from diskpart's own output
REM after attaching — never guessed or auto-selected, specifically so this can never accidentally
REM target the real physical Windows disk instead of the newly-attached virtual one.
REM
REM NOTE on DISM options: some DISM builds don't recognize every documented Apply-FFU option
REM (e.g. /SkipPlatformCheck failed with exit code 87 on one recovery media used while building
REM this). Run "dism /Apply-Ffu /?" and only pass options your own build's help text lists — see
REM docs/07-troubleshooting.md #7 in the main repo if this happens to you.
REM ===========================================================================================

setlocal enabledelayedexpansion

set "DRIVE=%~d0"
if exist "%~dp0config.cmd" (call "%~dp0config.cmd") else (
    set "DEVICE_NAME=my-laptop"
    set "FFU_NAME=my-laptop.ffu"
    set "VHDX_NAME=my-laptop.vhdx"
)

set "FFUFILE=%DRIVE%\%FFU_NAME%"
set "VHDXFILE=%DRIVE%\%VHDX_NAME%"

set "LOGROOT=%DRIVE%\capture-logs"
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value ^| find "="') do set "DT=%%I"
set "STAMP=%DT:~0,8%-%DT:~8,6%"
set "LOGDIR=%LOGROOT%\%STAMP%"
mkdir "%LOGDIR%" 2>nul
set "LOG=%LOGDIR%\03-apply-ffu.log"

echo === 03-apply-ffu started %DATE% %TIME% === > "%LOG%"

echo.
echo === Step 1: Checking required files exist ===
if not exist "%FFUFILE%" (
    echo ERROR: FFU file not found: %FFUFILE%
    echo Run 02-capture-ffu.cmd first, or check FFU_NAME in config.cmd matches the actual filename.
    goto :end
)
for %%F in ("%FFUFILE%") do echo FFU found: %%F  (%%~zF bytes) >> "%LOG%"
for %%F in ("%FFUFILE%") do echo FFU found: %%~nxF  (%%~zF bytes)

if exist "%VHDXFILE%" (
    for %%F in ("%VHDXFILE%") do set "VHDXSIZE=%%~zF"
    echo.
    echo WARNING: %VHDXFILE% already exists ^(!VHDXSIZE! bytes^) - it may already contain a
    echo previous Apply-FFU result, complete or partial. Continuing will overwrite it.
    set /p OVERWRITECONFIRM="Type OVERWRITE-EXISTING-VHDX to proceed anyway, anything else to stop: "
    if /I not "!OVERWRITECONFIRM!"=="OVERWRITE-EXISTING-VHDX" (
        echo Cancelled by user - existing VHDX not overwritten. >> "%LOG%"
        echo Cancelled. Log: %LOG%
        goto :end
    )
    del /f "%VHDXFILE%" >> "%LOG%" 2>&1
)

echo.
echo === Step 2: Free space check ===
fsutil volume diskfree %DRIVE% > "%LOGDIR%\diskfree.txt" 2>&1
type "%LOGDIR%\diskfree.txt"
type "%LOGDIR%\diskfree.txt" >> "%LOG%"
echo.
echo Applying the FFU needs roughly as much free space as your original Windows partition used.
echo Compare "Total avail free bytes" above against that before continuing.
set /p SPACECONFIRM="Type ENOUGH-SPACE if there is clearly enough free space shown above, anything else to stop: "
if /I not "%SPACECONFIRM%"=="ENOUGH-SPACE" (
    echo Cancelled by user - insufficient space confirmed by user. >> "%LOG%"
    echo Cancelled. Log: %LOG%
    goto :end
)

echo.
echo === Step 3: Listing disks BEFORE creating the VHDX - note the number of the internal Windows
echo disk so we can make sure we never target it by accident ===
(
echo list disk
echo exit
) > "%TEMP%\dp_before.txt"
diskpart /s "%TEMP%\dp_before.txt" > "%LOGDIR%\diskpart-before.txt" 2>&1
type "%LOGDIR%\diskpart-before.txt"
type "%LOGDIR%\diskpart-before.txt" >> "%LOG%"

echo.
set /p PROTECTDISK="Type the disk number of the internal Windows disk shown above (never to be touched): "

echo.
echo === Step 4: Creating and attaching a fresh VHDX ===
(
echo create vdisk file=%VHDXFILE% maximum=2000000 type=expandable
echo select vdisk file=%VHDXFILE%
echo attach vdisk
echo list disk
echo exit
) > "%TEMP%\dp_create.txt"
diskpart /s "%TEMP%\dp_create.txt" > "%LOGDIR%\diskpart-create.txt" 2>&1
type "%LOGDIR%\diskpart-create.txt"
type "%LOGDIR%\diskpart-create.txt" >> "%LOG%"

echo.
echo The disk list above should show a NEW disk that was not in the BEFORE list - that is the
echo VHDX you just created and attached. Do not confuse it with disk %PROTECTDISK%.
set /p VHDXDISK="Type that NEW disk number: "

if "%VHDXDISK%"=="%PROTECTDISK%" (
    echo ERROR: user entered the protected source disk number for VHDXDISK. Refusing to continue. >> "%LOG%"
    echo ERROR: you entered the PROTECTED source disk number. Refusing to continue - applying the
    echo image there would overwrite the real Windows disk. Stopping.
    goto :end
)

echo.
echo === Step 5: Applying the FFU onto disk %VHDXDISK% ===
echo About to run:
echo   dism /Apply-FFU /ImageFile:%FFUFILE% /ApplyDrive:\\.\PhysicalDrive%VHDXDISK%
echo.
echo If your DISM build supports /SkipPlatformCheck and you need it, add it yourself after
echo confirming with "dism /Apply-Ffu /?" - it's deliberately not included by default here
echo (see docs/07-troubleshooting.md #7 in the main repo for why).
set /p APPLYCONFIRM="Type YES (all caps) to proceed: "
if /I not "%APPLYCONFIRM%"=="YES" (
    echo Cancelled by user before Apply-FFU. >> "%LOG%"
    echo Cancelled. Log: %LOG%
    goto :end
)

echo.
echo Running now - DISM's own live percentage progress stays visible below. This writes roughly
echo as much data as your original Windows partition used, so it can take a while.
echo === Step 5: Apply-FFU started %DATE% %TIME% (see dism-apply-detail.log for DISM's own log) === >> "%LOG%"
dism /Apply-FFU /ImageFile:%FFUFILE% /ApplyDrive:\\.\PhysicalDrive%VHDXDISK% /LogPath:"%LOGDIR%\dism-apply-detail.log"
set "APPLYRC=%ERRORLEVEL%"
echo === Step 5: Apply-FFU exited with code %APPLYRC% === >> "%LOG%"

if not "%APPLYRC%"=="0" (
    echo.
    echo ERROR: Apply-FFU exited with code %APPLYRC%. See %LOGDIR%\dism-apply-detail.log for detail.
    echo If this is exit code 87, see docs/07-troubleshooting.md #7 in the main repo.
    goto :end
)
echo.
echo Apply-FFU completed successfully (exit code 0).

echo.
echo === Step 6: Detaching the VHDX ===
(
echo select vdisk file=%VHDXFILE%
echo detach vdisk
echo exit
) > "%TEMP%\dp_detach.txt"
diskpart /s "%TEMP%\dp_detach.txt" > "%LOGDIR%\diskpart-detach.txt" 2>&1
type "%LOGDIR%\diskpart-detach.txt"
type "%LOGDIR%\diskpart-detach.txt" >> "%LOG%"

echo.
echo === Final state ===
for %%F in ("%VHDXFILE%") do echo Resulting VHDX: %%F  (%%~zF bytes)
for %%F in ("%VHDXFILE%") do echo Resulting VHDX: %%F  (%%~zF bytes) >> "%LOG%"
echo.
echo Done. Next: run 04-copy-logs-to-usb.cmd, then bring both drives back to the Mac.
echo Full log: %LOG%

:end
endlocal
