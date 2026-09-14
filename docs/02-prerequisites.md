# Prerequisites

## On the Mac (Apple Silicon)

| Tool | Install | Why |
|---|---|---|
| [Homebrew](https://brew.sh) | per its own instructions | Everything else below installs through it |
| QEMU + swtpm | `brew install qemu swtpm` (or `scripts/mac/03-install-qemu.sh`) | The emulation engine and a software TPM 2.0 (Windows 11 requires TPM) |
| A Docker runtime | [OrbStack](https://orbstack.dev) recommended, or Docker Desktop | Runs a disposable Linux container with `libguestfs`/`hivex` to inspect the disk image read-only, without installing those tools natively on the Mac |
| Free disk space | roughly 2-2.5x the used space on the source Windows partition | You'll have the offline-captured original *and* a working copy at the same time, at least temporarily |

Nothing else needs to be installed natively. The one deliberate exception to "run everything in a
container" is QEMU itself — an interactive GUI boot can't sensibly run nested inside a disposable
Linux container on macOS, so it's the one native install.

macOS mounts NTFS **read-only** by default (no third-party driver installed) — this matters later
for how files move between the Mac and the external hard drive. See
[the file-transfer-relay diagram](diagrams/file-transfer-relay.md) for why, and don't be tempted
to "fix" this by installing a third-party read-write NTFS driver just to save one hop — it works
fine without one.

## On the Windows side

- The physical machine, one more time, booted from a **WinRE/recovery/installation USB** whose
  Command Prompt supports `dism /Capture-FFU` — check with `dism /Capture-FFU /?`; if it errors,
  your media doesn't support it and you'll need newer install media (any reasonably recent
  Windows 10/11 installer USB should work).
- A **second, separate external hard drive** (NTFS is fine — it's Windows-native either way),
  with free space for both the `.ffu` capture and the resulting `.vhdx` — plan for roughly
  2x the used space on the source Windows partition, since both files exist at once mid-process.
- A **third, small USB flash drive** formatted FAT32 — used purely to shuttle small files (scripts,
  logs) between the Mac and the external drive, since the Mac can read FAT32 and write to it
  natively, but can only read the external drive's NTFS filesystem. See
  [file-transfer-relay.md](diagrams/file-transfer-relay.md).

You do **not** need networking, a full Windows boot, or any software installed inside Windows
itself for the capture — everything happens from the recovery environment.

## A note on DISM version differences

`dism /Apply-FFU` accepts different options on different Windows builds. One real run in this
project failed immediately with exit code 87 (`0x80070057`, invalid parameter) because
`/SkipPlatformCheck` wasn't recognized by that particular recovery media's DISM build. Always run
`dism /Apply-FFU /?` first and check what your build actually supports before assuming a flag from
someone else's writeup (including this one) applies verbatim — see
[troubleshooting #7](07-troubleshooting.md#7-applyffu-fails-with-exit-code-87-invalid-parameter).

Next: [Mac setup](03-mac-setup.md).
