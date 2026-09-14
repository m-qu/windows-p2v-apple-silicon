#!/bin/bash
# Attempt to boot the working copy with QEMU: OVMF UEFI firmware, emulated TPM 2.0 via swtpm,
# SATA/AHCI disk bus (built-in Windows driver, no VirtIO driver needed). Uses TCG software CPU
# emulation because an Apple Silicon host cannot hardware-virtualize an x86_64 guest — this is
# expected; the goal is a working boot, not native speed.
#
# A native macOS window (-display cocoa) opens directly. Only the working copy is ever touched —
# the original VHDX is never referenced by this script.
#
# IMPORTANT: stay at the computer for this. If Windows enters Automatic Repair, close the window
# rather than letting repair cycles run unattended — see docs/07-troubleshooting.md #8 for why
# that matters (it's what destroys a registry hive, not a hypothetical risk).

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

CONFIG="$SCRIPT_DIR/config.sh"
[[ -f "$CONFIG" ]] || { echo "ERROR: $CONFIG not found. Copy config.example.sh to config.sh and edit it first." >&2; exit 1; }
# shellcheck source=/dev/null
source "$CONFIG"

LOG_FILE="$REPO_ROOT/logs/04-boot-attempt-qemu.log"
VM_STATE_DIR="$REPO_ROOT/vm-state"
WORK_COPY="$IMAGE_DIR/$WORK_COPY_NAME"

mkdir -p "$REPO_ROOT/logs" "$VM_STATE_DIR/tpm"

log() {
    local level="$1"; shift
    local line="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    printf '%s\n' "$line" | tee -a "$LOG_FILE"
}
info() { log INFO "$@"; }
fatal() { log ERROR "$@"; exit 1; }

[[ -f "$WORK_COPY" ]] || fatal "Working copy not found: $WORK_COPY. Run 01-make-work-copy.sh first."
command -v qemu-system-x86_64 >/dev/null 2>&1 || fatal "qemu-system-x86_64 not found. Run 03-install-qemu.sh first."
command -v swtpm >/dev/null 2>&1 || fatal "swtpm not found. Run 03-install-qemu.sh first."

QEMU_PREFIX="$(brew --prefix qemu)"
OVMF_CODE="$QEMU_PREFIX/share/qemu/edk2-x86_64-code.fd"
OVMF_VARS_TEMPLATE="$QEMU_PREFIX/share/qemu/edk2-i386-vars.fd"
OVMF_VARS_WORK="$VM_STATE_DIR/OVMF_VARS-work.fd"

[[ -f "$OVMF_CODE" ]] || fatal "OVMF firmware not found at $OVMF_CODE. Check 'brew list qemu' for the real path and update this script."

if [[ ! -f "$OVMF_VARS_WORK" ]]; then
    [[ -f "$OVMF_VARS_TEMPLATE" ]] || fatal "OVMF vars template not found at $OVMF_VARS_TEMPLATE."
    cp -- "$OVMF_VARS_TEMPLATE" "$OVMF_VARS_WORK"
    info "Created per-VM UEFI vars file: $OVMF_VARS_WORK"
fi

TPM_SOCK="$VM_STATE_DIR/tpm/swtpm-sock"
if pgrep -f "swtpm socket.*$TPM_SOCK" >/dev/null 2>&1; then
    info "swtpm is already running for this VM state"
else
    info "Starting swtpm (emulated TPM 2.0)"
    rm -f -- "$TPM_SOCK"
    swtpm socket \
        --tpmstate dir="$VM_STATE_DIR/tpm" \
        --ctrl type=unixio,path="$TPM_SOCK" \
        --tpm2 \
        --log level=1,file="$REPO_ROOT/logs/swtpm.log" \
        --daemon
    sleep 1
    [[ -S "$TPM_SOCK" ]] || fatal "swtpm did not create its control socket at $TPM_SOCK"
fi

info "Starting QEMU: RAM=${QEMU_RAM_MB}MB SMP=${QEMU_SMP} disk=$WORK_COPY"
info "A native window should open (Cocoa display). Watch it directly — stay at the computer."
info "Full command and output are logged to $LOG_FILE"

{
    printf '\n=== QEMU boot attempt started %s ===\n' "$(date '+%Y-%m-%d %H:%M:%S')"
} >>"$LOG_FILE"

qemu-system-x86_64 \
    -name "${DEVICE_NAME:-windows-p2v}" \
    -machine q35,accel=tcg \
    -cpu max \
    -m "${QEMU_RAM_MB}" \
    -smp "${QEMU_SMP}" \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$OVMF_VARS_WORK" \
    -drive file="$WORK_COPY",format=vhdx,if=none,id=disk0,cache=writeback \
    -device ahci,id=ahci0 \
    -device ide-hd,drive=disk0,bus=ahci0.0 \
    -chardev socket,id=chrtpm,path="$TPM_SOCK" \
    -tpmdev emulator,id=tpm0,chardev=chrtpm \
    -device tpm-tis,tpmdev=tpm0 \
    -netdev user,id=net0 \
    -device e1000,netdev=net0 \
    -display cocoa \
    -usb -device usb-tablet \
    2>&1 | tee -a "$LOG_FILE"

info "QEMU exited. Review $LOG_FILE for anything logged before the window closed."
info "If Windows reached Automatic Repair repeatedly, see docs/07-troubleshooting.md #8 before retrying."
