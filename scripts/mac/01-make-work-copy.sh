#!/bin/bash
# Create a verified working copy of the offline-captured VHDX. Every later script operates only on
# this copy — the original is opened read-only here and never again.
#
# There is no previously-known checksum to compare against (this file was just captured for the
# first time) — this script computes one and treats it as the authoritative baseline going
# forward. Log it somewhere safe; if you ever need to confirm the original hasn't changed, this is
# what you compare against.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

CONFIG="$SCRIPT_DIR/config.sh"
[[ -f "$CONFIG" ]] || { echo "ERROR: $CONFIG not found. Copy config.example.sh to config.sh and edit it first." >&2; exit 1; }
# shellcheck source=/dev/null
source "$CONFIG"

LOG_FILE="$REPO_ROOT/logs/01-make-work-copy.log"
mkdir -p "$REPO_ROOT/logs"

log() {
    local level="$1"; shift
    local line="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    printf '%s\n' "$line" | tee -a "$LOG_FILE"
}
info() { log INFO "$@"; }
warn() { log WARN "$@"; }
fatal() { log ERROR "$@"; exit 1; }

[[ -d "$IMAGE_DIR" ]] || fatal "IMAGE_DIR not found: $IMAGE_DIR. Check config.sh."

if [[ -z "${ORIGINAL_VHDX_NAME:-}" ]]; then
    info "ORIGINAL_VHDX_NAME not set in config.sh — auto-detecting a single .vhdx in $IMAGE_DIR"
    mapfile -t candidates < <(find "$IMAGE_DIR" -maxdepth 1 -iname '*.vhdx' ! -iname "$WORK_COPY_NAME" -print)
    case "${#candidates[@]}" in
        0) fatal "No .vhdx file found in $IMAGE_DIR. Copy the offline-captured VHDX there first." ;;
        1) ORIGINAL_VHDX="${candidates[0]}" ;;
        *) fatal "Multiple .vhdx files found in $IMAGE_DIR; set ORIGINAL_VHDX_NAME explicitly in config.sh to pick one: ${candidates[*]}" ;;
    esac
else
    ORIGINAL_VHDX="$IMAGE_DIR/$ORIGINAL_VHDX_NAME"
fi
WORK_COPY="$IMAGE_DIR/$WORK_COPY_NAME"

[[ -f "$ORIGINAL_VHDX" ]] || fatal "Offline-captured VHDX not found: $ORIGINAL_VHDX"

if [[ -f "$WORK_COPY" ]]; then
    fatal "A working copy already exists at $WORK_COPY. Remove or rename it first if you want a fresh copy; this script refuses to overwrite an existing working copy."
fi

info "Computing baseline SHA-256 of $ORIGINAL_VHDX (read-only; first time this file has been hashed)"
original_sha256="$(shasum -a 256 "$ORIGINAL_VHDX" | awk '{print $1}')"
info "Baseline SHA-256: $original_sha256  <-- keep a record of this"

required_bytes="$(stat -f%z "$ORIGINAL_VHDX")"
avail_bytes="$(df -k "$IMAGE_DIR" | tail -1 | awk '{print $4 * 1024}')"
margin_bytes=$(( required_bytes / 10 ))
if (( avail_bytes < required_bytes + margin_bytes )); then
    fatal "Not enough free space for the working copy. Need ~$(( (required_bytes + margin_bytes) / 1024 / 1024 / 1024 )) GB, have $(( avail_bytes / 1024 / 1024 / 1024 )) GB free at $IMAGE_DIR."
fi
info "Free space check passed ($(( avail_bytes / 1024 / 1024 / 1024 )) GB available)"

info "Copying $ORIGINAL_VHDX -> $WORK_COPY (this can take a while for a large disk)"
if command -v rsync >/dev/null 2>&1; then
    rsync --progress -- "$ORIGINAL_VHDX" "$WORK_COPY"
else
    cp -- "$ORIGINAL_VHDX" "$WORK_COPY"
fi

info "Verifying working copy checksum"
copy_sha256="$(shasum -a 256 "$WORK_COPY" | awk '{print $1}')"
if [[ "$copy_sha256" != "$original_sha256" ]]; then
    warn "Working copy checksum ($copy_sha256) does not match the original ($original_sha256)."
    rm -f -- "$WORK_COPY"
    fatal "Copy verification failed. The bad copy was removed; rerun this script."
fi
info "Working copy verified identical to the original: $WORK_COPY"
info "Original VHDX was opened read-only and is unchanged."
info "Done. Log: $LOG_FILE"
