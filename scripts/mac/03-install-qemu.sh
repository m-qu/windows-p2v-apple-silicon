#!/bin/bash
# Install QEMU and swtpm (emulated TPM 2.0, required by Windows 11) via Homebrew. Idempotent —
# safe to rerun.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
LOG_FILE="$REPO_ROOT/logs/03-install-qemu.log"
mkdir -p "$REPO_ROOT/logs"

log() {
    local line="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    printf '%s\n' "$line" | tee -a "$LOG_FILE"
}

command -v brew >/dev/null 2>&1 || { echo "ERROR: Homebrew not found. Install it from https://brew.sh first." >&2; exit 1; }

for pkg in qemu swtpm; do
    if brew list --formula "$pkg" >/dev/null 2>&1; then
        log "SKIP: $pkg already installed"
    else
        log "INSTALL: $pkg"
        brew install "$pkg" 2>&1 | tee -a "$LOG_FILE"
    fi
done

QEMU_PREFIX="$(brew --prefix qemu)"
OVMF_CODE="$QEMU_PREFIX/share/qemu/edk2-x86_64-code.fd"
OVMF_VARS_TEMPLATE="$QEMU_PREFIX/share/qemu/edk2-i386-vars.fd"

log "Checking OVMF UEFI firmware files..."
[[ -f "$OVMF_CODE" ]] && log "OK: $OVMF_CODE" || log "WARNING: not found at $OVMF_CODE — check 'brew list qemu' for the real path and update 04-boot-attempt-qemu.sh if it differs."
[[ -f "$OVMF_VARS_TEMPLATE" ]] && log "OK: $OVMF_VARS_TEMPLATE" || log "WARNING: not found at $OVMF_VARS_TEMPLATE"

log "Done. qemu-system-x86_64: $(command -v qemu-system-x86_64 || echo 'not on PATH — restart your shell?')"
log "Done. swtpm: $(command -v swtpm || echo 'not on PATH — restart your shell?')"
