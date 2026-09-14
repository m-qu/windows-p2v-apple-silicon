# Promoting to a permanent UTM VM

[UTM](https://mac.getutm.app) shares QEMU's own engine under the hood, so a QEMU command line that
already boots correctly translates into a UTM VM — a normal GUI window, a VM library, and so on,
instead of running a shell script each time. The steps below are the actual verified path,
including the traps that aren't obvious from UTM's UI alone.

## Install UTM

```bash
brew install --cask utm
```

## Create the VM — pick "Other", not "Windows"

This is the first real trap: UTM's **"Windows"** quick-create wizard is built around *installing*
Windows from an ISO — it will not let you continue without picking a boot image, even if you
uncheck "Install Windows 10 or higher". There is no "skip the ISO, I already have a disk" option
on that screen.

**Use "Other" instead of "Windows"** as the OS type. It's the generic path, and it has no ISO
requirement — you go straight to hardware settings and, later, a Storage step where you can
**Import** an existing disk image instead of creating a new one.

1. **Emulate** (not Virtualize — the architecture mismatch between the Apple Silicon host and the
   x86_64 guest is exactly why emulation is needed here).
2. Operating system: **Other**.
3. Architecture: `x86_64`. System: `q35`.
4. Memory and CPU cores: whatever you used successfully with the QEMU script
   (`QEMU_RAM_MB` / `QEMU_SMP` if you overrode the defaults).
5. Storage: don't use the drive it creates by default. Add a drive via **New → Import…** and
   select your working-copy VHDX. Interface: **IDE** — on a q35 machine there's no legacy PCI IDE
   controller in the hardware at all, so UTM's "IDE" choice is implemented via the same
   AHCI-backed path the QEMU script already used; there's no separate "SATA" option in the list
   and none is needed.
6. Finish the wizard and open the new VM's settings (not the running VM — its settings/edit view).

## Two settings the wizard does *not* turn on for you

Check both of these in the VM's settings before ever booting it — neither is on by default even
though Windows 11 requires both:

- **QEMU tab → TPM 2.0 Device.** Windows 11 will not install or may misbehave without it. When you
  check it, UTM will also auto-check **Reset UEFI Variables** and **Preload Secure Boot Keys** —
  that's expected and correct for a VM that has never booted yet (it just means "start from a
  clean, valid Secure Boot key store"), and per UTM's own label, those two are one-time actions
  for the next boot only, not settings you need to manage again afterward.
- Confirm **UEFI Boot** is checked (it usually is by default, but verify).

**Click the main Save button at the bottom of the settings window after this** — not just closing
a sub-dialog. A drive added via Import (or any other change) that never hits the outer Save does
not persist; re-opening the VM's settings afterward is the only way to be sure it actually took
(see [troubleshooting #11](07-troubleshooting.md#11-utm-settings-that-look-saved-but-arent)).

## What "Import" actually does to your disk

Importing a foreign-format disk (a VHDX, here) does **not** just reference the file in place —
UTM converts it to qcow2 and copies the full converted result into its own VM bundle. Concretely,
that means:

- A second full-size copy of your disk gets created (a ~360 GB VHDX became a ~330 GB qcow2 copy in
  one real case) — budget disk space for both existing at once, at least temporarily.
- Your original VHDX is untouched and still valid on its own — it's just no longer what the VM
  actually boots from. Once you've confirmed the UTM VM boots correctly, that original working
  copy is redundant and safe to delete, if you no longer need it as a separate fallback.
- The `.utm` bundle (config + the new qcow2) is *not* a small pointer file — it physically contains
  the full disk. Moving or backing it up moves/backs up the whole thing.

See [troubleshooting #10](07-troubleshooting.md#10-utm-import-converts-and-duplicates-the-disk-not-a-reference)
for the exact commands to verify this if you want to check it on your own setup before trusting it.

## Verifying it actually worked

Before the first real boot, sanity-check what actually got saved (UTM's own display can lag or
misrepresent what's on disk after a chain of dialog edits):

```bash
find ~/Library/Containers/com.utmapp.UTM/Data/Documents -maxdepth 1 -name "*.utm"
# or wherever you opened/moved the .utm bundle from — check its config.plist:
plutil -p "/path/to/YourVM.utm/config.plist"
```

Confirm in the output: `"TPMDevice" => true`, `"UEFIBoot" => true`, and a non-empty `"Drive"` array
with an `ImageName` that looks like your real disk (not empty, not a fresh small placeholder).

## First boot

Boot it from UTM's UI and watch it directly, same caution as the raw QEMU script: if Windows
enters Automatic Repair repeatedly, close it rather than letting cycles run unattended (see
[troubleshooting #8](07-troubleshooting.md#8-automatic-repair-cycles-destroying-the-system-hive)).
A couple of one-time driver-detection reboots on the very first boot in a new environment can be
normal; the concern is specifically leaving it unattended for a long time.

## If you move the VM's folder afterward

Moving a `.utm` bundle on disk (e.g. `mv` from Finder or Terminal, to relocate it out of UTM's
default sandboxed storage folder into your own folder) works — UTM tracks each VM via a
security-scoped bookmark, and re-opening the moved bundle (File → Open, or drag it onto UTM)
re-registers it correctly from the new location. The one loose end: the *old* location stays
listed in UTM's VM library as an orphaned, empty entry, because UTM's own "Move" UI action was
never used. See
[troubleshooting #11](07-troubleshooting.md#11-utm-settings-that-look-saved-but-arent) for how to
find and remove that stale entry.

## Building the application matrix

Once the desktop is reachable, go through the applications that were actually installed on the
original machine and check them off one by one — pass/fail, plus anything that needed a driver
reinstall or license reactivation (some software ties licenses to hardware IDs, which can change
under emulation). This is manual, machine-specific work with no shortcut, but it's the actual
finish line for a P2V migration — the disk booting is necessary but not sufficient.

Next: if something didn't go as expected anywhere in this process, check
[troubleshooting](07-troubleshooting.md).
