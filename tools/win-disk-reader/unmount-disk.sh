#!/bin/bash
# Internal helper — not meant to be run directly. Invoked automatically inside the container by
# `win-disk-reader.sh stop` (via `docker exec`), which sets the required environment variables:
#   CONTAINER_MOUNT_POINT, NBD_DEVICE, CONTAINER_HOSTNAME
#
# The reverse of mount-disk.sh: stops smbd, unmounts the NTFS filesystem, and disconnects the
# nbd device. See ../README.md for the full picture.
set -uo pipefail

# ---- guard: refuse to run anywhere but inside the win-disk-reader container ----
# Catches the common mistake of running this file directly (e.g. from the Mac terminal or the
# IDE) instead of through `win-disk-reader.sh stop`, and fails with a clear message instead of a
# confusing error partway through.
die_not_in_container() {
  echo "[unmount-disk.sh] ERROR: $1" >&2
  echo "[unmount-disk.sh]        This script only runs inside the win-disk-reader container." >&2
  echo "[unmount-disk.sh]        From the Mac, run: ./win-disk-reader.sh stop" >&2
  exit 1
}

[ "$(uname -s)" = "Linux" ] || die_not_in_container "expected to run on Linux, detected '$(uname -s)'."
[ -f /.dockerenv ] || die_not_in_container "no /.dockerenv marker found — this doesn't look like a container."
for bin in qemu-nbd mountpoint pkill; do
  command -v "$bin" >/dev/null 2>&1 || die_not_in_container "required tool '$bin' not found — this doesn't look like the win-disk-reader image."
done
[ -n "${CONTAINER_HOSTNAME:-}" ] || die_not_in_container "CONTAINER_HOSTNAME env var is not set — not launched the way win-disk-reader.sh launches it."
[ "$(hostname)" = "$CONTAINER_HOSTNAME" ] || die_not_in_container "hostname mismatch: expected '$CONTAINER_HOSTNAME', got '$(hostname)' — this is some other container."

: "${CONTAINER_MOUNT_POINT:?}"
: "${NBD_DEVICE:?}"

if [ -f /run/smbd.pid ]; then
  kill "$(cat /run/smbd.pid)" 2>/dev/null || true
  rm -f /run/smbd.pid
fi
pkill smbd 2>/dev/null || true

if mountpoint -q "$CONTAINER_MOUNT_POINT" 2>/dev/null; then
  umount "$CONTAINER_MOUNT_POINT" && echo "[in-container] unmounted: $CONTAINER_MOUNT_POINT"
fi

qemu-nbd -d "$NBD_DEVICE" >/dev/null 2>&1 && echo "[in-container] disconnected: $NBD_DEVICE" || true
