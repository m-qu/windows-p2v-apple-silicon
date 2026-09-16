#!/bin/bash
# Internal helper — not meant to be run directly. Invoked automatically inside the container by
# `win-disk-reader.sh start` (via `docker exec`), which sets the required environment variables:
#   QCOW2_PATH, CONTAINER_MOUNT_POINT, NBD_DEVICE, SMB_SHARE_NAME, CONTAINER_HOSTNAME
#
# Connects the qcow2 disk read-only (qemu-nbd), finds and mounts the NTFS partition (ntfs-3g,
# read-only), and shares it read-only over SMB (smbd) so win-disk-reader.sh can mount it on the
# Mac. See ../README.md for the full picture and unmount-disk.sh for the reverse.
set -euo pipefail

# ---- guard: refuse to run anywhere but inside the win-disk-reader container ----
# Catches the common mistake of running this file directly (e.g. from the Mac terminal or the
# IDE) instead of through `win-disk-reader.sh start`, and fails with a clear message instead of a
# confusing error (or worse, attaching qemu-nbd to a device that doesn't exist) partway through.
die_not_in_container() {
  echo "[mount-disk.sh] ERROR: $1" >&2
  echo "[mount-disk.sh]        This script only runs inside the win-disk-reader container." >&2
  echo "[mount-disk.sh]        From the Mac, run: ./win-disk-reader.sh start" >&2
  exit 1
}

[ "$(uname -s)" = "Linux" ] || die_not_in_container "expected to run on Linux, detected '$(uname -s)'."
[ -f /.dockerenv ] || die_not_in_container "no /.dockerenv marker found — this doesn't look like a container."
for bin in qemu-nbd blkid blockdev partprobe smbd; do
  command -v "$bin" >/dev/null 2>&1 || die_not_in_container "required tool '$bin' not found — this doesn't look like the win-disk-reader image."
done
[ -n "${CONTAINER_HOSTNAME:-}" ] || die_not_in_container "CONTAINER_HOSTNAME env var is not set — not launched the way win-disk-reader.sh launches it."
[ "$(hostname)" = "$CONTAINER_HOSTNAME" ] || die_not_in_container "hostname mismatch: expected '$CONTAINER_HOSTNAME', got '$(hostname)' — this is some other container."

: "${QCOW2_PATH:?}"
: "${CONTAINER_MOUNT_POINT:?}"
: "${NBD_DEVICE:?}"
: "${SMB_SHARE_NAME:?}"

echo "[in-container] connecting $QCOW2_PATH via qemu-nbd (read-only)..."
qemu-nbd --read-only -c "$NBD_DEVICE" -f qcow2 "$QCOW2_PATH"

echo "[in-container] waiting for partitions to be recognized..."
DEV_NAME="$(basename "$NBD_DEVICE")"
for i in $(seq 1 20); do
  partprobe "$NBD_DEVICE" >/dev/null 2>&1 || true
  if [ -d "/sys/class/block/${DEV_NAME}p1" ]; then
    break
  fi
  sleep 0.5
done

# This container has no udev, so the kernel knows about the partitions (under
# /sys) but never creates their device files under /dev; create them manually.
echo "[in-container] creating device nodes for partitions..."
for p in /sys/class/block/"${DEV_NAME}"p*; do
  [ -d "$p" ] || continue
  name="$(basename "$p")"
  devnum="$(cat "$p/dev")"
  major="${devnum%%:*}"
  minor="${devnum##*:}"
  [ -e "/dev/$name" ] || mknod -m 660 "/dev/$name" b "$major" "$minor"
done

echo "[in-container] looking for the NTFS partition (largest one, to skip the recovery partition)..."
NTFS_DEV=""
NTFS_SIZE=0
for dev in $(blkid -t TYPE=ntfs -o device); do
  size="$(blockdev --getsize64 "$dev")"
  if [ "$size" -gt "$NTFS_SIZE" ]; then
    NTFS_SIZE="$size"
    NTFS_DEV="$dev"
  fi
done
if [ -z "$NTFS_DEV" ]; then
  echo "[in-container] ERROR: no NTFS partition found." >&2
  exit 1
fi
echo "[in-container] found partition: $NTFS_DEV (size: $NTFS_SIZE bytes)"

mkdir -p "$CONTAINER_MOUNT_POINT"
mount -t ntfs-3g -o ro,uid=0,gid=0 "$NTFS_DEV" "$CONTAINER_MOUNT_POINT"
echo "[in-container] mounted (read-only) at $CONTAINER_MOUNT_POINT"

mkdir -p /etc/samba /run/samba
cat > /etc/samba/smb.conf <<EOF
[global]
workgroup = WORKGROUP
server min protocol = SMB2
security = user
map to guest = Bad User
log level = 1
pid directory = /run/samba
lock directory = /run/samba
private dir = /run/samba

[$SMB_SHARE_NAME]
path = $CONTAINER_MOUNT_POINT
guest ok = yes
read only = yes
browseable = yes
EOF

smbd --foreground --no-process-group &
echo $! > /run/smbd.pid
sleep 1
if ! kill -0 "$(cat /run/smbd.pid)" 2>/dev/null; then
  echo "[in-container] ERROR: smbd failed to start." >&2
  exit 1
fi
echo "[in-container] smbd ready (pid $(cat /run/smbd.pid))"
