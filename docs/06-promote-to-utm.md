# Promoting to a permanent UTM VM

[UTM](https://mac.getutm.app) shares QEMU's own engine under the hood, so a QEMU command line that
already boots correctly translates directly into a UTM VM — you get the same working configuration
with a normal GUI window, a VM library, snapshots, and so on, instead of running a shell script
each time.

## Steps

1. In UTM, create a new virtual machine: **Emulate** (not Virtualize — the architecture mismatch
   between an Apple Silicon host and an x86_64 guest is exactly why emulation is needed here, same
   as the QEMU script).
2. Architecture: `x86_64`. System: `q35` (matches `-machine q35` in the boot script).
3. Firmware: UEFI, and enable the TPM 2.0 module in UTM's settings (matches `-tpmdev
   emulator`/`-device tpm-tis` in the script).
4. CPU/RAM: match whatever you used successfully in `scripts/mac/04-boot-attempt-qemu.sh`
   (`QEMU_SMP` / `QEMU_RAM_MB` if you overrode the defaults).
5. Disk: point it at your **working copy** VHDX (not the original) — the same file the script was
   already booting successfully.
6. Boot it once from UTM's own UI to confirm it reaches the desktop the same way the script did.

From here, UTM's VM is your day-to-day Windows environment. The original offline-captured VHDX and
the shell scripts in this repo remain useful as a recovery path — if the working copy ever gets
into a bad state, `scripts/mac/01-make-work-copy.sh` can always produce a fresh one from the
untouched original.

## Building the application matrix

Once the desktop is reachable, go through the applications that were actually installed on the
original machine and check them off one by one — pass/fail, plus anything that needed a driver
reinstall or license reactivation (some software ties licenses to hardware IDs, which can change
under emulation). This is manual, machine-specific work with no shortcut, but it's the actual
finish line for a P2V migration — the disk booting is necessary but not sufficient.

Next: if something didn't go as expected anywhere in this process, check
[troubleshooting](07-troubleshooting.md).
