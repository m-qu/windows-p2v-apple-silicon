@echo off
REM Copy this file to config.cmd (same folder) and edit if you want to override the defaults.
REM config.cmd is not meant to be committed anywhere — it's just a couple of SET lines.
REM If config.cmd doesn't exist, every script here falls back to these same defaults, so copying
REM this file is optional, not required.

set DEVICE_NAME=my-laptop
set FFU_NAME=%DEVICE_NAME%.ffu
set VHDX_NAME=%DEVICE_NAME%.vhdx
