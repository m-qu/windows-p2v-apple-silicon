# win-disk-reader

Read-only access to the **C: drive** of your Windows VM, **without powering the VM on**. Useful
once you have a working UTM VM (see [../../docs/06-promote-to-utm.md](../../docs/06-promote-to-utm.md))
and just need to pull a few files off the disk — booting the VM only to copy a handful of files
is slow (full CPU emulation) and file transfer through UTM's shared folder is slow on top of that.

The C: drive shows up as a normal folder on the Mac (`mnt/`) — browse it in Finder or the
terminal like any other mounted volume.

## Why this exists

The VM's disk is a static file on the Mac's filesystem — as long as the VM itself isn't running,
that file can be read directly, without emulating a CPU at all.

## How it works

The VM's disk is a QCOW2 image (see
[troubleshooting #10](../../docs/07-troubleshooting.md#10-utm-import-converts-and-duplicates-the-disk-not-a-reference)
for how it got that way). macOS has no built-in way to read QCOW2 or NTFS, so this tool does the
work inside a disposable Linux container (via OrbStack), which does have all the necessary tools,
and bridges the result back to the Mac:

1. **Connect the disk** — `qemu-nbd --read-only` inside the container exposes the qcow2 file as a
   block device (`/dev/nbd0`), without ever mounting it read-write.
2. **Find and mount the Windows partition** — the partition table is read, the *largest* NTFS
   partition is picked (so a small recovery partition is never mistaken for C:), and it's mounted
   with `ntfs-3g -o ro`.
3. **Re-export it over SMB** — mounting a filesystem inside a container's own mount namespace does
   not make it visible on the Mac by itself (OrbStack's `~/OrbStack/docker/...` view only shows
   named volumes, not runtime mounts). So a `smbd` inside the container shares the mounted folder
   read-only, published **only on `127.0.0.1`** — never reachable from the network.
4. **Mount that SMB share on the Mac** — macOS's built-in `mount_smbfs` connects to it at `mnt/`
   next to this script. From this point on, `mnt/` behaves like a normal, read-only, mounted
   drive.

Three independent read-only layers (bind mount, `qemu-nbd --read-only`, `ntfs-3g -o ro`) mean
there is no path for anything in this pipeline to write to the real Windows disk.

`stop` reverses every step in order — unmounts the Mac side, stops `smbd`, unmounts NTFS,
disconnects `qemu-nbd`, removes the container — so `mnt/` goes back to being an empty, ordinary
folder.

## Requirements

- OrbStack installed and running (`docker --context orbstack info` must succeed).
- Your VM must be **powered off**. `start` refuses to run otherwise (checked via `pgrep` against
  the VM's own UUID, configured in `config.env`).

## Configure

```bash
cp config.example.env config.env
```

Edit `config.env`:

```bash
QCOW2_HOST_DIR="$HOME/virtual-machines/YourVM.utm/Data"  # the .utm bundle's Data folder
VM_RUNNING_MATCH="..."                                    # your VM's UUID — see the comments in
                                                           # config.example.env for how to find it
```

`config.env` is gitignored on purpose — it's specific to your machine and paths, and should never
be committed.

## Files

| File | Purpose |
|---|---|
| `config.example.env` | Template — copy to `config.env` and edit for your setup. |
| `config.env` | Your actual settings (gitignored, not committed). |
| `Dockerfile` | Builds the image with `qemu-utils`, `ntfs-3g`, `parted`, and `samba` preinstalled. |
| `mount-disk.sh` | Runs inside the container: connects the disk, mounts NTFS, starts `smbd`. |
| `unmount-disk.sh` | Runs inside the container: the reverse of the above. |
| `win-disk-reader.sh` | The controller you actually run, on the Mac. |
| `mnt/` | Where the C: drive appears once `start` succeeds. Empty otherwise. Gitignored. |
| `output/` | Destination folder for the `extract` command. Gitignored. |
| `logs/win-disk-reader.log` | Timestamped log of every run. Gitignored. |

## Usage

```bash
./win-disk-reader.sh check    # run every precondition check, make no changes
./win-disk-reader.sh start    # build the image, connect the disk, mount it at mnt/
./win-disk-reader.sh status   # is the container running? is mnt/ mounted?
./win-disk-reader.sh stop     # unmount everything and remove the container
```

While it's running, `mnt/` is a normal read-only folder — open it in Finder, `cp` files out of
it, `find`/`grep` through it, whatever you need.

Two extra commands exist as a fallback in case the SMB mount ever misbehaves:

```bash
./win-disk-reader.sh shell                          # interactive shell inside the container
./win-disk-reader.sh extract "Users/name/Desktop/file.docx"   # copy one path into output/
```

Run `./win-disk-reader.sh --help` any time for the full command list.

## Important: never run this alongside the actual VM

This tool and the VM both read the same qcow2 file. `start` checks that the VM is off before
doing anything, but the reverse isn't automatic — **always run `stop` before turning the VM on**,
to avoid two things touching the disk image at once.

## A note on why `mount-disk.sh` creates device nodes manually

The container has no `udev` running. The kernel recognizes the qcow2's partitions (visible under
`/sys/class/block/nbd0p*`) as soon as `qemu-nbd` connects them, but without `udev` their device
files under `/dev` are never created automatically. `mount-disk.sh` creates them itself with
`mknod`, reading the major/minor numbers straight from `/sys`, before looking for the NTFS
partition with `blkid`.
