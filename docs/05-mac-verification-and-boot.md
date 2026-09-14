# Mac-side: verification and boot

With the offline-captured VHDX copied into your `IMAGE_DIR` (see
[`scripts/mac/config.sh`](../scripts/mac/config.example.sh)), everything from here runs on the
Mac.

## Step 1 — make a verified working copy

```bash
cd scripts/mac
./01-make-work-copy.sh
```

This computes a SHA-256 of the VHDX you just copied over (there's no previously-known checksum to
compare against — this file was just created, so this run establishes the baseline), copies it to
a working copy, and verifies the copy is byte-identical before letting you use it. **Every later
step operates only on the working copy — the original stays untouched, read-only, forever.** This
matters: if a boot attempt goes wrong and damages the working copy (see
[troubleshooting #8](07-troubleshooting.md#8-automatic-repair-cycles-destroying-the-system-hive)),
you can always make a fresh working copy from the still-good original instead of starting the
whole capture over.

## Step 2 — check the registry hives before ever booting

```bash
./02-check-all-hives.sh
```

Read-only. Spins up a disposable Docker container, mounts the working copy's VHDX with
`libguestfs`, downloads the five core registry hives (`SYSTEM`, `SOFTWARE`, `SAM`, `SECURITY`,
`DEFAULT`), and validates each one structurally with `hivexregedit --export`. A real, healthy
`SYSTEM` hive is normally tens of megabytes; anything in the low kilobytes is a red flag for
truncation (see [troubleshooting #8](07-troubleshooting.md#8-automatic-repair-cycles-destroying-the-system-hive)
for what caused that in this project). It also confirms which partition is actually the Windows
volume before assuming it, and reports whether `HiberbootEnabled` is set — expected to still show
as `1` here if it was `1` on the original machine (that's a persisted setting, not itself a
problem for an *offline* capture — see [the root-cause writeup](01-problem-and-root-cause.md)).

Do not skip this step. It's cheap (a few minutes) compared to finding out mid-boot that a hive was
already broken.

## Step 3 — boot it

```bash
./04-boot-attempt-qemu.sh
```

Starts an emulated TPM 2.0 (`swtpm`) and boots the working copy under QEMU with OVMF UEFI
firmware, matching what Windows 11 requires. A native macOS window opens directly.

**Stay at the computer for this.** If Windows enters Automatic Repair, close the window rather
than letting repair cycles run unattended — see
[troubleshooting #8](07-troubleshooting.md#8-automatic-repair-cycles-destroying-the-system-hive)
for exactly why that matters. A few Automatic Repair cycles before reaching the desktop can be
normal on the first boot of a P2V'd disk in a new environment (driver detection, etc.); the
concern is specifically leaving it running unattended for a long time.

If it reaches the desktop: that's it — the hard part is done. If it doesn't, re-check the hive
check output from Step 2 and the [troubleshooting guide](07-troubleshooting.md) before trying
again.

Next: [promote this into a permanent UTM VM](06-promote-to-utm.md), or start using it as-is.
