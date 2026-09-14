#!/bin/bash
# Read-only structural check of all five core registry hives (SYSTEM, SOFTWARE, SAM, SECURITY,
# DEFAULT) on the working copy, using guestfish + hivexregedit inside a disposable Docker
# container — nothing is installed natively on the Mac, and the working copy is only ever mounted
# read-only.
#
# Also runs list-filesystems first, before assuming a specific partition is the Windows volume —
# don't hardcode a partition number without checking; disk layouts vary.
#
# Also greps the exported SYSTEM hive for HiberbootEnabled (Fast Startup) purely for visibility —
# see docs/01-problem-and-root-cause.md for why its value doesn't indicate a problem for an
# offline capture specifically.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

CONFIG="$SCRIPT_DIR/config.sh"
[[ -f "$CONFIG" ]] || { echo "ERROR: $CONFIG not found. Copy config.example.sh to config.sh and edit it first." >&2; exit 1; }
# shellcheck source=/dev/null
source "$CONFIG"

LOG_FILE="$REPO_ROOT/logs/02-check-all-hives.log"
mkdir -p "$REPO_ROOT/logs"
WORK_COPY="$IMAGE_DIR/$WORK_COPY_NAME"
DOCKER_IMAGE="ubuntu:24.04"

log() {
    local level="$1"; shift
    local line="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    printf '%s\n' "$line" | tee -a "$LOG_FILE"
}
info() { log INFO "$@"; }
fatal() { log ERROR "$@"; exit 1; }

[[ -f "$WORK_COPY" ]] || fatal "Working copy not found: $WORK_COPY. Run 01-make-work-copy.sh first."
command -v docker >/dev/null 2>&1 || fatal "docker CLI is not available."
docker --context "$DOCKER_CONTEXT" info >/dev/null 2>&1 || fatal "Docker context '$DOCKER_CONTEXT' is not reachable. Is it running? (check config.sh)"

info "Starting temporary container to check filesystem layout and all five core hives (read-only)"

{
docker --context "$DOCKER_CONTEXT" run --rm -i \
    --privileged \
    -e LIBGUESTFS_BACKEND=direct \
    -e LIBGUESTFS_MEMSIZE=4096 \
    -v "$WORK_COPY:/work/disk.vhdx" \
    "$DOCKER_IMAGE" bash -s <<'CONTAINER_EOF'
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "=== Installing libguestfs-tools + hivex + kernel package ==="
apt-get update -qq
apt-get install -y -qq libguestfs-tools libhivex-bin linux-image-generic >/dev/null

DISK=/work/disk.vhdx

echo ""
echo "=== Filesystem layout ==="
guestfish --ro -a "$DISK" run : list-filesystems

echo ""
echo "=== Finding the Windows partition automatically (checking each NTFS partition for"
echo "/Windows/System32/config/SYSTEM, rather than assuming a fixed partition number — a disk"
echo "can have more than one NTFS partition, e.g. Recovery, so partition NUMBER alone isn't enough) ==="
WINPART=""
for part in $(guestfish --ro -a "$DISK" run : list-filesystems | awk -F: '{print $1}'); do
    if guestfish --ro -a "$DISK" -m "$part" is-file /Windows/System32/config/SYSTEM 2>/dev/null | grep -qi true; then
        WINPART="$part"
        echo "Found Windows partition: $part"
        break
    fi
done
[[ -n "$WINPART" ]] || { echo "ERROR: could not find a partition containing /Windows/System32/config/SYSTEM."; exit 1; }

mkdir -p /tmp/hives

echo ""
echo "=== Downloading hive files from $WINPART (read-only) ==="
guestfish --ro -a "$DISK" -m "$WINPART" <<GUESTFISH_EOF
download /Windows/System32/config/SYSTEM /tmp/hives/SYSTEM
download /Windows/System32/config/SOFTWARE /tmp/hives/SOFTWARE
download /Windows/System32/config/SAM /tmp/hives/SAM
download /Windows/System32/config/SECURITY /tmp/hives/SECURITY
download /Windows/System32/config/DEFAULT /tmp/hives/DEFAULT
GUESTFISH_EOF

echo ""
echo "=== File sizes (a real SYSTEM/SOFTWARE hive is normally several MB; anything in the low KB"
echo "range for SYSTEM specifically is a red flag for truncation — see docs/07-troubleshooting.md #8)"
ls -la /tmp/hives/

echo ""
echo "=== Structural validity check per hive (hivexregedit --export, kept per-hive under /tmp) ==="
for hive in SYSTEM SOFTWARE SAM SECURITY DEFAULT; do
    printf '%-10s ' "$hive:"
    if [[ ! -s "/tmp/hives/$hive" ]]; then
        echo "DOWNLOAD FAILED (file missing or empty)"
        continue
    fi
    filesize="$(stat -c%s "/tmp/hives/$hive")"
    prefix="HKEY_LOCAL_MACHINE\\$hive"
    [[ "$hive" == "DEFAULT" ]] && prefix='HKEY_USERS\.DEFAULT'
    if hivexregedit --export --prefix "$prefix" "/tmp/hives/$hive" '\' >"/tmp/export_$hive.reg" 2>/tmp/export_err; then
        lines="$(wc -l < "/tmp/export_$hive.reg" | tr -d ' ')"
        echo "OK (${filesize} bytes on disk, exported $lines lines)"
    else
        echo "FAILED"
        echo "  --- error ---"
        sed 's/^/  /' /tmp/export_err
    fi
done

echo ""
echo "=== HiberbootEnabled (Fast Startup) in the exported SYSTEM hive — informational only ==="
if [[ -s /tmp/export_SYSTEM.reg ]]; then
    grep -i -B2 HiberbootEnabled /tmp/export_SYSTEM.reg || echo "Not present in the export."
else
    echo "SYSTEM export not available (see failure above)."
fi
CONTAINER_EOF
} 2>&1 | tee -a "$LOG_FILE"

info "Done. Full transcript: $LOG_FILE"
