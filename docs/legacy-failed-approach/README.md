# The abandoned live-capture approach

Kept deliberately, in full, as documented history — not because any of it should be reused, but
because the debugging trail here is often more useful than the final answer if you're working on
something adjacent to this exact problem. If you just want the working approach, you don't need
this file; see the main [docs/](../01-problem-and-root-cause.md) instead.

## What was tried

1. A live capture tool (Disk2vhd, using a VSS snapshot while Windows was running) produced a VHDX
   of the source disk.
2. VMware Fusion was tried first as the virtualization layer — and ruled out immediately: Fusion
   on Apple Silicon has no x86_64 guest support at all. Its own log confirmed this directly:
   ```
   Guest: Status upon boot failure: Unsupported
   Guest: Status upon boot failure: No compatible bootloader found
   Guest: Status upon boot failure: No Media
   ```
3. QEMU (with OVMF UEFI firmware and an emulated TPM 2.0 via `swtpm`) replaced Fusion as the
   emulation layer. The VHDX still would not boot — Windows went straight into Automatic Repair
   every time.

## Diagnosing it

Standard, non-destructive repair steps were tried first and got nowhere:

- `chkdsk /f` on every partition: no filesystem problems reported.
- `SrtTrail.txt` (WinRE's own repair log): `Number of root causes = 0`.
- `bootrec /fixmbr`, `/fixboot`, `/rebuildbcd`: no change.

The actual failure signature pointed somewhere more specific:
`DISM /revertpendingactions` failed with `0xd000014c` while loading
`C:\Windows\System32\config\DEFAULT`, and a plain `reg load` reported the configuration registry
database as corrupt. `RegBack` (Windows's own hive-backup folder) was empty, ruling out the
easiest possible fix.

### Building a working diagnostic pipeline (and the bugs hit along the way)

Rather than trust WinRE's own limited tools, the plan became: read the offline registry hives
directly, using `libguestfs` + `hivex` inside a disposable Docker container (so nothing had to be
installed natively on the Mac). Getting this actually working surfaced several real, independent
bugs, in order:

1. **`supermin: failed to find a suitable kernel (host_cpu=aarch64)`** — a plain `ubuntu:24.04`
   container shares the host kernel and ships no kernel package, but libguestfs's internal
   `supermin` helper needs one to boot its own internal appliance VM. Fixed by installing
   `linux-image-generic` in the container first.
2. **A heredoc silently doing nothing** — `docker run ... | tee -a log <<'EOF' ... EOF` attaches
   the heredoc to `tee`, not `docker run`, in a pipeline — a shell parsing rule, not a bug in any
   of the tools involved. Fixed by wrapping the whole `docker run` invocation in a `{ ... }` group
   and piping the group.
3. **`virt-win-reg`'s `CurrentControlSet` alias not resolving** — its own alias resolution left the
   literal string `CurrentControlSet` unresolved instead of mapping it to the real `ControlSetNNN`,
   so lookups through it failed even though the key existed. Fixed by reading
   `HKEY_LOCAL_MACHINE\SYSTEM\Select` directly instead.

### The actual finding

With the pipeline finally working, reading the offline `SYSTEM` hive directly showed
`HiberbootEnabled = 1` — Fast Startup was enabled on the source machine at the moment the live
capture was taken.

Independently, attempting to mount the same NTFS volume read-write with `ntfs-3g` (to apply a
registry fix) failed on its own terms:
```
The disk contains an unclean file system (0, 0).
Metadata kept in Windows cache, refused to mount.
```
`remove_hiberfile` alone didn't clear this — what worked was running libguestfs's `ntfsfix`
immediately before the read-write mount.

**Two unrelated tools — a registry reader and a filesystem driver — independently flagged the same
condition.** Fast Startup enabled + a live VSS snapshot (instead of a clean, full shutdown) leaves
the disk in a state that some import and repair paths can't reconcile, even though it looks
completely fine to `chkdsk`.

## Why fixing the flag wasn't enough

Flipping `HiberbootEnabled` to `0` in the offline hive is trivial and worth doing — but it only
prevents the problem on a *future* capture. The disk that was already captured live, with the flag
on, already has that inconsistency baked into its specific captured state. Attempting to boot it
anyway and let Windows "fix itself" does not help:

> After a few unattended Automatic Repair cycles on a completely fresh working copy — no commands
> run against it, nothing changed by hand — the `SYSTEM` hive had shrunk to 8 KB, containing only
> one key. Windows's own repair logic, with no `RegBack` to fall back to, had effectively
> destroyed the hive rather than recovered it.

This is the actual reason the live-capture path was abandoned rather than pursued further: the
disk gets *more* broken every time you try to boot it, not less. See
[the working approach](../01-problem-and-root-cause.md#the-fix-capture-offline-instead) for what
was done instead.
