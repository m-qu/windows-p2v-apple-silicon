#!/usr/bin/env bash
# Read-only access controller for a Windows VM disk's C: drive, without powering on the VM.
#
# Mounts the VM's qcow2 disk read-only inside a disposable container (qemu-nbd + ntfs-3g), then
# re-exports it over a loopback-only SMB share so it shows up as a normal folder on the Mac at
# mnt/. See README.md for the full mechanism. Run with -h/--help for the command list.
set -Eeuo pipefail

print_help() {
  cat <<'EOF'
win-disk-reader — read-only access to a Windows VM's C: drive, without booting the VM.

Usage: ./win-disk-reader.sh <command> [args]

Commands:
  check              Run all precondition checks only; makes no changes.
  build              Build the Docker image (qemu-utils, ntfs-3g, parted, samba).
  start              Build the image, connect the disk, and mount C: read-only at mnt/.
  status             Report full state: image built?, container not-created/stopped/running?,
                     mnt/ mounted?, and flag a stale mount if the container isn't running.
  stop               Unmount everything and remove the container (back to original state).
                     Safe to run any time, including when nothing is running.
  shell              Open an interactive shell inside the running container.
  extract <path>     Copy one file/folder from C: (path relative to C:) into output/.

Options:
  -h, --help         Show this help message and exit.

Examples:
  ./win-disk-reader.sh start
  ./win-disk-reader.sh extract "Users/name/Desktop/file.docx"
  ./win-disk-reader.sh stop

Important: never run 'start' while the actual VM is powered on, and always run 'stop' before
turning that VM on — both read the same disk file. See README.md for details.
EOF
}

case "${1:-}" in
  -h|--help)
    print_help
    exit 0
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONFIG="$SCRIPT_DIR/config.env"
[[ -f "$CONFIG" ]] || { echo "ERROR: $CONFIG not found. Copy config.example.env to config.env and edit it first." >&2; exit 1; }
# shellcheck source=config.example.env
source "$CONFIG"

MNT_DIR="$SCRIPT_DIR/mnt"
OUTPUT_DIR="$SCRIPT_DIR/output"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/win-disk-reader.log"
QCOW2_PATH="$QCOW2_HOST_DIR/$QCOW2_FILENAME"
QCOW2_CONTAINER_PATH="/vm-data/$QCOW2_FILENAME"

mkdir -p "$MNT_DIR" "$OUTPUT_DIR" "$LOG_DIR"

log() {
  local level="$1"; shift
  local ts; ts="$(date '+%Y-%m-%d %H:%M:%S')"
  echo "[$ts] [$level] $*" | tee -a "$LOG_FILE"
}

trap 'log ERROR "Script failed at line $LINENO."' ERR

docker_orb() { docker --context "$DOCKER_CONTEXT" "$@"; }

# "running" | "stopped" (exists but not running) | "absent" (doesn't exist at all)
container_state() {
  if docker_orb ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER_NAME"; then
    echo "running"
  elif docker_orb ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER_NAME"; then
    echo "stopped"
  else
    echo "absent"
  fi
}

# "yes" | "no" | "unknown" (couldn't tell within the time budget)
#
# Listing mounts is normally instant, but macOS's `mount` can itself block for a while if this
# exact path is mid-teardown from a previous abrupt unmount (observed: same multi-minute stall as
# the umount/diskutil calls in cmd_stop, for the same underlying reason). Bounded so 'status'
# stays usable precisely when you'd want to check it — right after a rough stop.
mac_mount_state() {
  local tmpfile; tmpfile="$(mktemp)"
  ( mount >"$tmpfile" 2>/dev/null ) </dev/null &
  local pid=$! waited=0
  while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 3 ]; do
    sleep 1
    waited=$((waited + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    disown "$pid" 2>/dev/null || true
    rm -f "$tmpfile"
    echo "unknown"
    return
  fi
  wait "$pid" 2>/dev/null
  if grep -q " $MNT_DIR " "$tmpfile" 2>/dev/null; then
    echo "yes"
  else
    echo "no"
  fi
  rm -f "$tmpfile"
}

require_running_container() {
  if [ "$(container_state)" != "running" ]; then
    log ERROR "Container '$CONTAINER_NAME' is not running. Run './win-disk-reader.sh start' first."
    return 1
  fi
}

# ---------- preflight checks ----------

check_docker() {
  if ! docker_orb info >/dev/null 2>&1; then
    log ERROR "OrbStack/Docker is not reachable. Open OrbStack first."
    return 1
  fi
  log INFO "OrbStack/Docker: OK"
}

check_source_file() {
  if [ ! -f "$QCOW2_PATH" ]; then
    log ERROR "Disk file not found: $QCOW2_PATH"
    return 1
  fi
  if [ ! -r "$QCOW2_PATH" ]; then
    log ERROR "Disk file is not readable: $QCOW2_PATH"
    return 1
  fi
  log INFO "Disk file: OK ($QCOW2_PATH)"
}

check_vm_not_running() {
  if pgrep -f "$VM_RUNNING_MATCH" >/dev/null 2>&1; then
    log ERROR "The VM is currently running. Shut it down first."
    return 1
  fi
  log INFO "VM is off: OK"
}

check_port_free() {
  if nc -z "$SMB_BIND_ADDR" "$SMB_HOST_PORT" 2>/dev/null; then
    log ERROR "Port ${SMB_BIND_ADDR}:${SMB_HOST_PORT} is already in use."
    return 1
  fi
  log INFO "SMB port is free: OK"
}

check_no_stale_container() {
  if [ "$(container_state)" != "absent" ]; then
    log WARN "A previous container named '$CONTAINER_NAME' already exists (leftover from a prior start/stop). Run 'stop' first."
    return 1
  fi
  log INFO "No leftover container: OK"
}

cmd_check() {
  log INFO "=== preflight check ==="
  local ok=1
  check_docker            || ok=0
  check_source_file       || ok=0
  check_vm_not_running    || ok=0
  check_port_free         || ok=0
  check_no_stale_container|| ok=0
  if [ "$ok" -eq 1 ]; then
    log INFO "Everything is ready."
    return 0
  fi
  log ERROR "Preflight check failed; fix the items above."
  return 1
}

# ---------- commands ----------

cmd_build() {
  log INFO "=== building image $IMAGE_NAME ==="
  docker_orb build -t "$IMAGE_NAME" "$SCRIPT_DIR" 2>&1 | tee -a "$LOG_FILE"
  log INFO "Build finished."
}

cmd_start() {
  cmd_check
  # Always rebuild (not only when the image is missing) so changes to
  # mount-disk.sh/unmount-disk.sh never get stuck in a stale cached image;
  # Docker's layer cache keeps this fast.
  cmd_build

  log INFO "Starting container '$CONTAINER_NAME'..."
  docker_orb run -d --privileged \
    --name "$CONTAINER_NAME" \
    --hostname "$CONTAINER_HOSTNAME" \
    -v "$QCOW2_HOST_DIR":/vm-data:ro \
    -v "$OUTPUT_DIR":/out \
    -p "${SMB_BIND_ADDR}:${SMB_HOST_PORT}:445" \
    -e QCOW2_PATH="$QCOW2_CONTAINER_PATH" \
    -e CONTAINER_MOUNT_POINT="$CONTAINER_MOUNT_POINT" \
    -e NBD_DEVICE="$NBD_DEVICE" \
    -e SMB_SHARE_NAME="$SMB_SHARE_NAME" \
    -e CONTAINER_HOSTNAME="$CONTAINER_HOSTNAME" \
    "$IMAGE_NAME" >>"$LOG_FILE" 2>&1

  log INFO "Connecting the disk and mounting NTFS (read-only) inside the container..."
  docker_orb exec "$CONTAINER_NAME" /usr/local/bin/mount-disk.sh 2>&1 | tee -a "$LOG_FILE"

  log INFO "Mounting SMB on the Mac at $MNT_DIR ..."
  local i
  for i in $(seq 1 10); do
    # -o soft: if the container ever dies abruptly instead of via a clean 'stop', a hard mount
    # would block filesystem calls (including umount) for a long time waiting on the dead SMB
    # server (observed: minutes) instead of failing fast.
    if mount_smbfs -N -o soft "//guest@${SMB_BIND_ADDR}:${SMB_HOST_PORT}/${SMB_SHARE_NAME}" "$MNT_DIR" 2>>"$LOG_FILE"; then
      log INFO "Ready. The C: drive is available read-only at: $MNT_DIR"
      return 0
    fi
    sleep 1
  done
  log ERROR "Mounting on the Mac side failed; see the log: $LOG_FILE"
  return 1
}

cmd_status() {
  log INFO "=== status ==="

  if docker_orb image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    log INFO "Image:     built ($IMAGE_NAME)"
  else
    log INFO "Image:     not built yet (run 'build' or 'start')"
  fi

  local c_state; c_state="$(container_state)"
  case "$c_state" in
    running) log INFO "Container: running" ;;
    stopped) log INFO "Container: exists, but stopped (leftover — run 'stop' to clean it up)" ;;
    absent)  log INFO "Container: does not exist" ;;
  esac

  local mounted; mounted="$(mac_mount_state)"

  case "$mounted" in
    unknown)
      log WARN "Mac mount: could not determine right now — a previous unmount of this path may still be resolving in the background (this normally clears within a couple of minutes; try again shortly)."
      ;;
    yes)
      if [ "$c_state" != "running" ]; then
        log WARN "Mac mount: STALE — $MNT_DIR is still mounted but the container is not running. Run 'stop' to clean it up."
      else
        log INFO "Mac mount: active ($MNT_DIR)"
      fi
      ;;
    no)
      log INFO "Mac mount: not mounted"
      ;;
  esac
}

cmd_stop() {
  log INFO "=== stopping ==="
  local did_something=0

  # Mac-side mount first, container second — deliberately, and only after getting this backwards
  # once already. Doing the container first (killing smbd via unmount-disk.sh/`docker rm -f`)
  # means the Mac's unmount always then talks to an already-dead server — turning the slow/wedged
  # path from an edge case (container died before 'stop' was even called) into the COMMON case
  # (every normal stop kills smbd first, by definition). Unmounting from the Mac while smbd is
  # still alive and responsive is what makes the normal case instant, as it did before that
  # reorder. The bounded wait below still protects the case where the container is already dead
  # when 'stop' runs — the container cleanup after it doesn't depend on the mount's state anyway.
  #
  # Treat "unknown" (mac_mount_state couldn't tell within its own time budget) the same as "yes"
  # here — attempting an unnecessary unmount is harmless, skipping a needed one isn't.
  if [ "$(mac_mount_state)" != "no" ]; then
    # Normally instant. But if the container died abruptly (killed rather than cleanly stopped),
    # the client can be left holding a TCP connection to a peer that vanished without closing it —
    # a kernel-level condition (observed: several minutes) that neither 'soft' mounts nor `kill`
    # on the umount process can shortcut, since it's stuck below userspace. So: try for a few
    # seconds, and if it's not done by then, hand it off to the background and return immediately
    # instead of making the user wait on an OS-level timeout. It reliably clears on its own.
    # Every stream is explicitly redirected on the whole group (not per-command) so this job
    # inherits none of the parent script's file descriptors — otherwise, if it ends up orphaned
    # a few lines down, whatever is capturing this script's own output (a pipe, a log wrapper,
    # this being run non-interactively) stays open and "hangs" waiting for EOF until the orphan
    # itself finally exits, even though the script has already returned.
    ( umount "$MNT_DIR" || diskutil unmount force "$MNT_DIR" ) </dev/null >>"$LOG_FILE" 2>&1 &
    local umount_pid=$! waited=0
    while kill -0 "$umount_pid" 2>/dev/null && [ "$waited" -lt 5 ]; do
      sleep 1
      waited=$((waited + 1))
    done
    if kill -0 "$umount_pid" 2>/dev/null; then
      disown "$umount_pid" 2>/dev/null || true
      log WARN "The Mac-side mount isn't responding (the container likely died abnormally). Unmounting it in the background — this can take a couple of minutes; check 'status' later to confirm it's cleared."
    else
      wait "$umount_pid" 2>/dev/null
      log INFO "Mac-side mount removed."
    fi
    did_something=1
  fi

  # Container cleanup doesn't depend on the mount's state at all — safe to do after it
  # unconditionally, and it's always fast (no network filesystem involved).
  local c_state; c_state="$(container_state)"
  if [ "$c_state" = "running" ]; then
    docker_orb exec "$CONTAINER_NAME" /usr/local/bin/unmount-disk.sh 2>&1 | tee -a "$LOG_FILE" || true
  fi
  if [ "$c_state" != "absent" ]; then
    docker_orb rm -f "$CONTAINER_NAME" >>"$LOG_FILE" 2>&1 || true
    log INFO "Container removed."
    did_something=1
  fi

  if [ "$did_something" -eq 1 ]; then
    log INFO "Done."
  else
    log INFO "Nothing was running; already in the original state."
  fi
}

cmd_shell() {
  require_running_container
  docker_orb exec -it "$CONTAINER_NAME" bash
}

cmd_extract() {
  require_running_container
  local rel="${1:?Provide a path relative to C:, e.g. Users/name/Desktop/file.docx}"
  docker_orb exec "$CONTAINER_NAME" bash -c "
    mkdir -p \"/out/\$(dirname '$rel')\" &&
    cp -a \"$CONTAINER_MOUNT_POINT/$rel\" \"/out/$rel\"
  "
  log INFO "Copied to: $OUTPUT_DIR/$rel"
}

# ---------- entry point ----------

case "${1:-}" in
  check)   cmd_check ;;
  build)   cmd_build ;;
  start)   cmd_start ;;
  status)  cmd_status ;;
  stop)    cmd_stop ;;
  shell)   cmd_shell ;;
  extract) shift; cmd_extract "$@" ;;
  *)
    echo "usage: $0 {check|build|start|status|stop|shell|extract <relative-path>}"
    echo "Run '$0 --help' for details."
    exit 1
    ;;
esac
