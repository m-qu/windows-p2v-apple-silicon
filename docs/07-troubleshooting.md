# Troubleshooting

Nine real failures hit while building this, each with its actual root cause and fix — not
speculative advice. If you're stuck, look for the symptom that matches yours before assuming your
situation is unique.

## 1. VMware Fusion won't boot the x86_64 disk at all

**Symptom:** VMware Fusion on Apple Silicon accepts an x86_64 disk image but the VM never boots.
Its own `vmware.log` shows:
```
Guest: Status upon boot failure: Unsupported
Guest: Status upon boot failure: No compatible bootloader found
Guest: Status upon boot failure: No Media
```

**Root cause:** VMware Fusion on Apple Silicon only supports ARM guest types — there is no x86_64
guest support at all, confirmed by Broadcom/VMware's own documentation and, independently, by this
log evidence.

**Fix:** Use QEMU/UTM instead. This isn't a configuration problem to work around.

## 2. `supermin: failed to find a suitable kernel (host_cpu=aarch64)`

**Symptom:** Running `virt-inspector`/`guestfish` inside a plain `ubuntu:24.04` Docker container
fails with this error.

**Root cause:** libguestfs's internal `supermin` helper needs an actual kernel image plus matching
`/lib/modules` to boot its own internal helper VM. A plain container image shares the host kernel
and ships no kernel package at all.

**Fix:** `apt-get install -y linux-image-generic` inside the container before calling any
libguestfs tool. Already baked into `scripts/mac/02-check-all-hives.sh`.

## 3. A heredoc silently does nothing in a piped command

**Symptom:** `docker run ... bash -s -- ARG 2>&1 | tee -a log <<'EOF' ... EOF` runs without error,
but the container's script appears to do nothing — `tee` just echoes the heredoc's literal text.

**Root cause:** in `cmd1 | cmd2 <<EOF`, the heredoc attaches to `cmd2` (`tee`), not `cmd1` (`docker
run`) — a real shell parsing rule, not a Docker bug. `docker run`'s stdin ends up empty.

**Fix:** wrap the whole `docker run ... <<'EOF' ... EOF` in a `{ ... }` group and pipe the group,
not the individual command: `{ docker run ... <<'EOF' ... EOF; } | tee -a log`.

## 4. `virt-win-reg`'s `CurrentControlSet` alias doesn't resolve

**Symptom:** `virt-win-reg ... 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\...'` fails with `path
not found in this hive`, even though the key clearly exists.

**Root cause:** `CurrentControlSet` is a symlink-like alias that has to be resolved to a real
`ControlSetNNN`; `virt-win-reg`'s own alias resolution didn't do this correctly and left the
literal string unresolved.

**Fix:** read `HKEY_LOCAL_MACHINE\SYSTEM\Select` directly to find which `ControlSetNNN` is
actually current, and address that directly instead of relying on the alias.

## 5. ntfs-3g refuses to mount read-write: "unclean file system"

**Symptom:**
```
The disk contains an unclean file system (0, 0).
Metadata kept in Windows cache, refused to mount.
```
even when the mount is explicitly requested read-write, and even after `remove_hiberfile`.

**Root cause:** this is ntfs-3g's own dirty-volume detection — independent confirmation of the
same live-VSS-capture-with-Fast-Startup problem described in
[the root-cause writeup](01-problem-and-root-cause.md). `remove_hiberfile` alone doesn't clear it,
because the flag being detected isn't specifically about the hibernation file.

**Fix:** run libguestfs's `ntfsfix` on the partition immediately before mounting read-write. Full
working sequence: `ntfsfix /dev/sdaN` → `mount-options rw /dev/sdaN /` → proceed.

## 6. macOS can read the external NTFS drive but can't write to it

**Symptom:** copying a file *off* the external hard drive onto the Mac works fine; deleting or
writing to that same drive fails with `Read-only file system`, even though `diskutil info` reports
the *media* itself isn't read-only.

**Root cause:** macOS's built-in NTFS driver is read-only by design; there's no third-party
read-write NTFS driver (ntfs-3g, Paragon, etc.) installed, deliberately, to keep the Mac's native
software footprint minimal.

**Fix:** don't fight it — do write/delete operations on the Windows side, where NTFS access is
native, and use a small FAT32 USB flash drive (which macOS *can* write to) as the relay for
scripts and logs in both directions. See
[`diagrams/file-transfer-relay.md`](diagrams/file-transfer-relay.md). This is exactly why
`scripts/windows/01-copy-to-external-drive.cmd` and `04-copy-logs-to-usb.cmd` exist as separate
steps instead of a single direct Mac-to-external-drive copy.

## 7. `Apply-FFU` fails with exit code 87 (invalid parameter)

**Symptom:**
```
DISM FFU Provider: ... CFfuManager::InternalValidateOptions(hr:0x80070057)
```
immediately, before any data is written.

**Root cause:** an option on the `dism /Apply-FFU` command line (in this project's case,
`/SkipPlatformCheck`) wasn't recognized by that specific recovery media's DISM build. Different
Windows install media ship different DISM versions with different supported options for the same
command.

**Fix:** run `dism /Apply-Ffu /?` on your actual recovery media first and only pass options its
own help text lists. Don't copy someone else's exact command line assuming every DISM build
supports the same flags.

## 8. Automatic Repair cycles destroying the SYSTEM hive

**Symptom:** after leaving a boot attempt running unattended through several Automatic Repair
cycles, the `SYSTEM` registry hive shrinks to a few kilobytes — containing only one key — and the
disk is now *more* broken than before the boot attempt.

**Root cause:** Windows's own repair logic, when it can't fully recover a hive (especially with no
`RegBack` backup available), can end up writing out a near-empty hive rather than leaving the
original in place. This happens on the disk itself, not because of anything the emulator does.

**Fix:** there is no in-place fix once this happens — restore from a known-good working copy (this
is exactly why the working-copy step keeps the original completely untouched). Going forward:
treat repeated Automatic Repair cycles as a stop signal. Close the VM and investigate rather than
letting it retry on its own.

## 9. Live capture + Fast Startup = inconsistent state on import

**Symptom:** the disk shows no filesystem errors (`chkdsk` clean, `SrtTrail.txt` reports zero root
causes) and yet still won't boot, always landing in Automatic Repair.

**Root cause and fix:** this is the project's central finding — see
[`01-problem-and-root-cause.md`](01-problem-and-root-cause.md) for the full diagnostic trail.
Short version: a live VSS-based capture with Fast Startup enabled at capture time produces a
disk state that some import/repair paths can't reconcile, even though nothing about it looks
broken to a standard filesystem check. Capturing the same disk fully offline instead
(`dism /Capture-FFU` with Windows completely powered off) avoids the problem at the source.
