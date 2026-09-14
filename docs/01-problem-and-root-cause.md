# The problem, and why it happens

## Starting point

- An existing Windows 11 x86_64 installation on a physical laptop, with applications already
  installed, needs to run on an Apple Silicon Mac (ARM64) — without keeping the physical laptop
  around as an ongoing dependency, without new hardware, and without paid virtualization software
  if a free path works.
- Architecture mismatch (ARM64 host, x86_64 guest) rules out hardware-accelerated virtualization
  entirely. The only way to run this *exact, unmodified* disk is CPU emulation — QEMU's TCG
  engine. Slower than native, but that trade-off was accepted from the start: the goal is a
  working boot, not speed.
- VMware Fusion was ruled out first and fastest: on Apple Silicon, Fusion cannot boot x86_64
  guests at all — confirmed both by the vendor's own documentation and, empirically, by its own
  log file reporting `Status upon boot failure: Unsupported` / `No compatible bootloader found`
  when actually attempted.

## First attempt: live capture

The obvious approach: capture the running Windows disk with a live-imaging tool (Disk2vhd, which
uses a VSS snapshot), convert if needed, and boot the result in QEMU with UEFI + emulated TPM
(Windows 11 requires both).

**Result: the VM never reaches the desktop.** Windows boots into Automatic Repair every time.

## Diagnosing it — what didn't work and what did

Standard non-destructive repair steps were tried first and ruled out:
- `chkdsk /f` on both partitions: no filesystem problems reported.
- `SrtTrail.txt` (WinRE's own repair log): `Number of root causes = 0`.
- `bootrec /fixmbr`, `/fixboot`, `/rebuildbcd`: no change.

The actual failure signature: `DISM /revertpendingactions` failed with `0xd000014c` while loading
`C:\Windows\System32\config\DEFAULT`, and `reg load` reported the configuration registry database
as corrupt. `RegBack` (Windows's own hive backup folder) was empty, so there was no last-known-good
hive to fall back to.

This specific signature — a registry hive that a live tool can't load — is a known pattern in
physical-to-virtual (P2V) migrations, and does **not** by itself prove the underlying data is
corrupted. Two independent tools ended up confirming the same root cause from different angles:

1. **The registry itself**: reading the offline `SYSTEM` hive directly (bypassing the WinRE `reg
   load` failure by mounting the volume in a Linux container with `libguestfs`/`hivex` instead)
   showed `HiberbootEnabled = 1` — Fast Startup was **on** at the moment the live capture was
   taken.
2. **The filesystem driver, independently**: attempting to mount the same NTFS volume read-write
   with `ntfs-3g` (to apply a registry fix) failed with its own, unrelated error:
   ```
   The disk contains an unclean file system (0, 0).
   Metadata kept in Windows cache, refused to mount.
   The NTFS partition is in an unsafe state. Please resume and shutdown
   Windows fully (no hibernation or fast restarting), or mount the volume
   read-only with the 'ro' mount option.
   ```

Two unrelated tools — a registry reader and an NTFS driver — independently flagged the exact same
condition. **Fast Startup being enabled, combined with capturing a live VSS snapshot instead of a
clean shutdown, leaves the disk in a state that looks structurally fine to `chkdsk` but is
inconsistent enough that some import/repair paths choke on it.**

## The trap: fixing the flag doesn't undo the damage already done

The registry flag itself is easy to flip offline (`HiberbootEnabled = 0` in the offline `SYSTEM`
hive), and doing so is worth trying — but it only prevents the problem on a *future* capture. On
the disk that was **already captured live** with the flag on, the inconsistency is already baked
into that specific captured state. Attempting to boot that disk and let Windows "fix itself" via
Automatic Repair does not help — it actively makes things worse:

> After a few unattended Automatic Repair cycles, the `SYSTEM` hive on one working copy shrank to
> 8 KB — containing only a single key. Windows's own repair logic, unable to fully recover
> (there were no `RegBack` backups to fall back to), had effectively destroyed the hive rather
> than fixing it. This happened on a **fresh, untouched copy**, with no commands run against it —
> proof the destruction is inherent to booting this specific disk state, not caused by anything
> done to it externally.

**Lesson: never leave a P2V'd disk's boot attempt unattended.** If it enters Automatic Repair,
that is a stop signal, not something to wait out.

## The fix: capture offline instead

If a live VSS snapshot with Fast Startup enabled is what produces the inconsistent state, the fix
is to remove the "live" variable entirely: **capture the same physical disk while Windows is
completely powered off**, booted instead from external recovery media. Windows's own `DISM
/Capture-FFU` does exactly this — a block-level, offline image, with nothing running to write to
the disk during capture.

Applying that offline capture onto a fresh virtual disk (`DISM /Apply-FFU`) and booting **that**
in QEMU reached the Windows desktop normally. The `HiberbootEnabled` registry setting was still
present as `1` in the new capture (it's a persisted OS *setting*, not itself a defect) — but
because nothing was running when the disk was imaged this time, the inconsistent on-disk state
that the live/VSS method produced never had a chance to occur.

Next: [prerequisites](02-prerequisites.md) for both sides, or jump straight to
[Windows-side offline capture](04-windows-offline-capture.md) if your Mac side is already set up.
