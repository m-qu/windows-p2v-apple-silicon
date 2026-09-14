# Mac-side setup

## Tools policy: containers first, native only when unavoidable

This project's guiding rule for what to install where:

1. **Headless/CLI inspection work runs inside a disposable Docker container** — specifically,
   reading and validating the registry hives inside the VHDX. There's no reason to install
   `libguestfs-tools` natively on macOS for something that only needs to run once per check and
   leaves nothing behind when the container exits.
2. **Interactive GUI work runs natively** — QEMU with a display can't sensibly run nested inside a
   throwaway Linux container, so it's installed via Homebrew directly. This is the one native
   install in this whole project.

## Install QEMU and swtpm

```bash
brew install qemu swtpm
```

Or run [`scripts/mac/03-install-qemu.sh`](../scripts/mac/03-install-qemu.sh), which does the same
thing idempotently and logs what it did.

Confirm the OVMF UEFI firmware Homebrew installed alongside QEMU:

```bash
brew --prefix qemu
# then check for:
#   <prefix>/share/qemu/edk2-x86_64-code.fd   (UEFI firmware code)
#   <prefix>/share/qemu/edk2-i386-vars.fd     (UEFI vars template)
```

Windows 11 requires TPM 2.0 — `swtpm` provides an emulated one; the boot script starts it
automatically.

## Set up a Docker runtime

Any Docker-compatible runtime works; [OrbStack](https://orbstack.dev) is a lightweight option on
macOS. The hive-check script (`scripts/mac/02-check-all-hives.sh`) expects a Docker context —
by default it's configured for a context named `orbstack`; if you're using plain Docker Desktop,
edit `DOCKER_CONTEXT` in your `config.sh` (or just use the `default` context).

## Configure this repo for your paths

```bash
cd scripts/mac
cp config.example.sh config.sh
```

Edit `config.sh`:

```bash
DEVICE_NAME="my-laptop"                 # short name, used only in log messages
IMAGE_DIR="$HOME/Develop/windows-image" # where your VHDX files will live
WORK_COPY_NAME="work-copy.vhdx"         # filename for the verified working copy
DOCKER_CONTEXT="orbstack"               # or "default", or whatever `docker context ls` shows
```

`config.sh` is gitignored on purpose — it's specific to your machine and paths, and should never
be committed.

Next: [Windows-side offline capture](04-windows-offline-capture.md).
