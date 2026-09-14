# Copy this file to config.sh (same directory) and edit for your setup.
# config.sh is gitignored — it's specific to your machine and is never committed.

# Short name for your device, used only in log messages.
DEVICE_NAME="my-laptop"

# Where your VHDX files live. The offline-captured VHDX you bring back from the Windows side
# should be copied in here before running 01-make-work-copy.sh.
IMAGE_DIR="$HOME/Develop/windows-image"

# Filename (not full path) of the offline-captured VHDX you copied into IMAGE_DIR.
# 01-make-work-copy.sh auto-detects a single *.vhdx in IMAGE_DIR if this is left blank, but you
# can pin it explicitly if you keep more than one VHDX in that folder.
ORIGINAL_VHDX_NAME=""

# Filename for the verified working copy this project creates and boots. Never the same as
# ORIGINAL_VHDX_NAME.
WORK_COPY_NAME="work-copy.vhdx"

# Docker context to use for the read-only hive-check container. Run `docker context ls` to see
# your options — "default" works for plain Docker Desktop; OrbStack users typically have an
# "orbstack" context.
DOCKER_CONTEXT="orbstack"

# QEMU boot resources — override here if 8 GB RAM / 4 vCPU doesn't fit your Mac.
QEMU_RAM_MB="${QEMU_RAM_MB:-8192}"
QEMU_SMP="${QEMU_SMP:-4}"
