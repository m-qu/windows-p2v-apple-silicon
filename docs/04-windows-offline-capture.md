# Windows-side: offline capture

Everything in this section runs **on the physical Windows machine**, booted from recovery media —
not on the Mac, and not from a normal Windows boot. This is the one deliberate, one-time use of
the physical machine this whole approach requires.

## Why files hop through a USB flash drive

macOS can read an NTFS-formatted external drive, but mounts it **read-only** by default. Windows,
of course, can read and write both NTFS and FAT32 natively. So:

- Getting these scripts *from* the Mac *to* the external NTFS drive can't be a direct copy from
  the Mac — the Mac can write to a FAT32 USB flash drive, then Windows copies from that USB onto
  the NTFS external drive.
- Getting logs *back* from the external drive to the Mac works the same way in reverse — Windows
  copies from the NTFS drive onto the FAT32 USB, and the Mac reads that USB directly.

Full picture: [`diagrams/file-transfer-relay.md`](diagrams/file-transfer-relay.md).

## Step 1 — get the scripts onto the external drive

1. On the Mac, copy `scripts/windows/` onto the FAT32 USB flash drive (the recovery/boot media).
2. Boot the Windows machine from that USB, get to **Troubleshoot → Advanced options → Command
   Prompt**.
3. Connect the external hard drive too, alongside the boot USB.
4. From the USB drive's Command Prompt, run:
   ```
   01-copy-to-external-drive.cmd
   ```
   It lists volumes and asks you to identify the external hard drive — it never guesses a drive
   letter. It's safe to re-run.

## Step 2 — capture the disk offline

From the folder you just copied, on the external hard drive:

```
02-capture-ffu.cmd
```

This runs `dism /Capture-FFU` against the *physical* Windows disk while Windows is completely
powered off — nothing is running to write to the disk during capture, which is the entire point
(see [the root-cause writeup](01-problem-and-root-cause.md) for why that matters). It shows you
the disk list, asks you to type the source disk number yourself, shows the exact command before
running it, and requires a typed `YES` before it touches anything. This step can take 30-90+
minutes depending on how much data is on the disk — let it finish completely.

## Step 3 — apply the capture onto a VHDX

```
03-apply-ffu.cmd
```

This creates a blank expandable VHDX on the external drive, attaches it, runs `dism /Apply-FFU`
to write the captured image onto it, then detaches it. Watch for:

- It asks you to note the *source* disk number first, purely so it can refuse to ever apply the
  image onto that disk by mistake.
- `dism /Apply-FFU`'s own live percentage progress stays visible on screen the whole time (this
  step writes as much data as your original Windows partition used, so it can take a while) —
  DISM also writes its own detailed log via `/LogPath` at the same time, so nothing is lost even
  though the console isn't redirected.
- If this fails immediately with exit code 87, see
  [troubleshooting #7](07-troubleshooting.md#7-applyffu-fails-with-exit-code-87-invalid-parameter)
  before assuming something is broken — it's very likely a DISM-version option mismatch, not a
  real problem with your capture.

## Step 4 — bring the logs back

```
04-copy-logs-to-usb.cmd
```

Copies every log this process produced back onto the USB flash drive, so you only need to carry
the small USB back to the Mac — the external hard drive (with the new VHDX on it) can travel back
separately, or stay connected if you want to retry something.

## What you should have now

- `<something>.ffu` — the offline capture. Safe to delete once the VHDX below is confirmed copied
  and working; it's a large intermediate file with no further use after that.
- `<something>.vhdx` — the actual result. Bring the external hard drive back to the Mac and copy
  this file into your `IMAGE_DIR` (see [Mac setup](03-mac-setup.md)).

Next: [Mac-side verification and boot](05-mac-verification-and-boot.md).
