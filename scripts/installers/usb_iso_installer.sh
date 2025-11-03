#!/usr/bin/env bash
set -euo pipefail
# Usage:
#   sudo ./write-os-usb.sh /dev/sdX {ubuntu|arch|debian} [ISO_PATH_OR_URL]
# Notes:
#   - Pass the WHOLE DISK (e.g., /dev/sda), NOT a partition like /dev/sda1.
#   - This overwrites the device with the installer image.
#   - Minimal on purpose: no checksums, no extra prompts, no wipefs.

DEV="${1:-}"; OS="${2:-}"; SRC="${3:-}"
[[ -z "${DEV}" || -z "${OS}" ]] && { echo "Usage: $0 /dev/sdX {ubuntu|arch|debian} [iso-path-or-url]"; exit 1; }

# Pick a default ISO/URL if none provided
UB_VER="${UB_VER:-24.04.1}"
DB_VER="${DB_VER:-12.6.0}"
case "$OS" in
  ubuntu)
    SRC="${SRC:-https://old-releases.ubuntu.com/releases/${UB_VER}/ubuntu-${UB_VER}-desktop-amd64.iso}"
    ;;
  arch)
    SRC="${SRC:-https://mirror.rackspace.com/archlinux/iso/latest/archlinux-x86_64.iso}"
    ;;
  debian)
    SRC="${SRC:-https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-${DB_VER}-amd64-netinst.iso}"
    ;;
  *) echo "OS must be one of: ubuntu | arch | debian"; exit 1;;
esac

# If SRC is a URL, fetch to /tmp; else use it as a local path
case "$SRC" in
  http://*|https://*)
    ISO="/tmp/$(basename "$SRC")"
    wget -O "$ISO" "$SRC"
    ;;
  *)
    ISO="$SRC"
    ;;
esac

# Unmount anything on the device (non-destructive; just in case)
umount "${DEV}"?* 2>/dev/null || true

# Write the image directly to the WHOLE device
dd if="$ISO" of="$DEV" bs=4M status=progress oflag=direct conv=fsync

# Light touch: ask kernel to re-read the table (safe to ignore if it fails)
blockdev --rereadpt "$DEV" 2>/dev/null || true
echo "✓ Done. $DEV now contains a bootable $OS installer."
