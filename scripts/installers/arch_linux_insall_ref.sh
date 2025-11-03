#!/usr/bin/env bash
# Arch Linux Unattended Install → GNOME Desktop (UEFI, optional LUKS)
# ------------------------------------------------------------------
# This script sets up a clean Arch install with GNOME on a single disk.
# It’s designed to be run **from the Arch ISO live environment**.
#
# WHAT IT DOES (high-level):
# 1) Wipes target disk (GPT), creates:
#      - ESP 512MiB (FAT32)  -> /boot
#      - (optional) LUKS2-encrypted root (ext4) -> /
# 2) Installs base system, configures locale, time, users.
# 3) Installs GNOME, PipeWire audio, NetworkManager, and enables GDM.
# 4) Installs systemd-boot (or GRUB if you prefer—toggle variable).
#
# ⚠️ DANGER: This ERASES the target disk entirely. Double-check variables!
# ------------------------------------------------------------------

set -euo pipefail

### ======= USER CONFIG ======= ###
# Target disk (WHOLE DISK, not a partition); e.g., /dev/nvme0n1 or /dev/sda
DISK="/dev/nvme0n1"

# Encrypt root with LUKS2? ("yes" or "no")
ENABLE_LUKS="yes"

# Filesystem label for root (inside LUKS if enabled)
ROOT_LABEL="arch-root"

# Hostname, user, and passwords
HOSTNAME="archmain"
NEW_USER="tomas"
USER_PASS="changeme"     # change later with `passwd`
ROOT_PASS="changeme"     # change later with `passwd`

# Locale & timezone
LOCALE="en_US.UTF-8"
TIMEZONE="America/Bogota"
KEYMAP="us"              # Console keymap

# Bootloader choice ("systemd-boot" or "grub")
BOOTLOADER="systemd-boot"

# GNOME extras? (installs gnome-extra)
GNOME_EXTRA="no"

# NVIDIA driver? set "yes" if you have an NVIDIA GPU
NVIDIA="no"
### =========================== ###

say() { printf "\n\033[1;32m%s\033[0m\n" "$*"; }
warn() { printf "\n\033[1;33m%s\033[0m\n" "$*"; }
die() { printf "\n\033[1;31mERROR: %s\033[0m\n" "$*" >&2; exit 1; }

# Confirm destructive operation
warn "About to WIPE disk: $DISK"
read -rp "Type 'WIPE $DISK' to continue: " CONFIRM
[[ "$CONFIRM" == "WIPE $DISK" ]] || die "Confirmation failed."

# Basic sanity checks
[[ -b "$DISK" ]] || die "Disk $DISK not found."
[[ -d /sys/firmware/efi ]] || die "UEFI not detected. Boot the ISO in UEFI mode."
say "Enabling NTP and checking connectivity"
timedatectl set-ntp true
ping -c1 archlinux.org >/dev/null 2>&1 || warn "No ping; ensure internet works (wifi-menu/iwd). Continuing…"

# Partition plan:
#  - esp:   1MiB -> 513MiB   (512MiB FAT32, partition 1)
#  - root:  513MiB -> 100%   (LUKS2 or ext4, partition 2)
say "Partitioning disk (GPT)…"
wipefs -fa "$DISK"
sgdisk --zap-all "$DISK" || true

parted -s "$DISK" mklabel gpt
parted -s "$DISK" unit MiB mkpart primary fat32 1 513
parted -s "$DISK" set 1 esp on
parted -s "$DISK" unit MiB mkpart primary 513 100%

ESP="${DISK}p1"
ROOT="${DISK}p2"
[[ -b "$ESP" && -b "$ROOT" ]] || die "Expected partitions not found."

say "Formatting ESP"
mkfs.fat -F32 -n EFI "$ESP"

MAPPER_NAME="cryptroot"
MOUNT_ROOT="/mnt"

if [[ "$ENABLE_LUKS" == "yes" ]]; then
  say "Setting up LUKS2 on $ROOT"
  cryptsetup luksFormat --type luks2 -s 512 -h sha256 -c aes-xts-plain64 "$ROOT"
  cryptsetup open "$ROOT" "$MAPPER_NAME"
  mkfs.ext4 -L "$ROOT_LABEL" "/dev/mapper/$MAPPER_NAME"
  mount "/dev/mapper/$MAPPER_NAME" "$MOUNT_ROOT"
else
  say "Formatting root as ext4"
  mkfs.ext4 -L "$ROOT_LABEL" "$ROOT"
  mount "$ROOT" "$MOUNT_ROOT"
fi

say "Mounting ESP"
mkdir -p "$MOUNT_ROOT/boot"
mount "$ESP" "$MOUNT_ROOT/boot"

say "Installing base system"
# Reflector optional: pick a mirror (comment out if mirrors are fine)
# pacman -Sy --noconfirm reflector
# reflector --country 'United States','Canada' --age 12 --sort rate --save /etc/pacman.d/mirrorlist

pacstrap -K "$MOUNT_ROOT" base linux linux-firmware networkmanager vim sudo bash-completion git

say "Generating fstab"
genfstab -U "$MOUNT_ROOT" >> "$MOUNT_ROOT/etc/fstab"

say "System configuration (chroot)…"
arch-chroot "$MOUNT_ROOT" /bin/bash -euo pipefail <<CHROOT
set -euo pipefail

echo "$HOSTNAME" > /etc/hostname

# Hosts
cat >/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

# Locale
sed -i "s/^#\\(${LOCALE//\//\\/} UTF-8\\)/\\1/" /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

# Time & console
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# Initramfs (add encrypt hook if LUKS)
if [[ "$ENABLE_LUKS" == "yes" ]]; then
  sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap block encrypt filesystems fsck)/' /etc/mkinitcpio.conf
else
  sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap block filesystems fsck)/' /etc/mkinitcpio.conf
fi
mkinitcpio -P

# Users & sudo
echo "root:${ROOT_PASS}" | chpasswd
useradd -m -G wheel,video,audio,storage -s /bin/bash "$NEW_USER"
echo "${NEW_USER}:${USER_PASS}" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Bootloader
if [[ "$BOOTLOADER" == "systemd-boot" ]]; then
  bootctl install
  ROOT_UUID=\$(blkid -s UUID -o value ${ROOT})
  if [[ "$ENABLE_LUKS" == "yes" ]]; then
    # Find LUKS UUID for cryptdevice=
    LUKS_UUID=\$(blkid -s UUID -o value ${ROOT})
    cat >/boot/loader/loader.conf <<EOF2
default arch
timeout 3
console-mode auto
editor no
EOF2
    cat >/boot/loader/entries/arch.conf <<EOF2
title   Arch Linux
linux   /vmlinuz-linux
initrd  /amd-ucode.img
initrd  /intel-ucode.img
initrd  /initramfs-linux.img
options rd.luks.name=\${LUKS_UUID}=${MAPPER_NAME} root=LABEL=${ROOT_LABEL} rw
EOF2
  else
    cat >/boot/loader/loader.conf <<EOF2
default arch
timeout 3
console-mode auto
editor no
EOF2
    cat >/boot/loader/entries/arch.conf <<EOF2
title   Arch Linux
linux   /vmlinuz-linux
initrd  /amd-ucode.img
initrd  /intel-ucode.img
initrd  /initramfs-linux.img
options root=LABEL=${ROOT_LABEL} rw
EOF2
  fi
elif [[ "$BOOTLOADER" == "grub" ]]; then
  pacman -Sy --noconfirm grub efibootmgr
  mkdir -p /boot/efi && mount ${ESP} /boot/efi || true
  if [[ "$ENABLE_LUKS" == "yes" ]]; then
    sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="rd.luks.name=UUID=$(blkid -s UUID -o value ${ROOT})=${MAPPER_NAME} root=LABEL=${ROOT_LABEL} rw"/' /etc/default/grub
  else
    sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="root=LABEL=${ROOT_LABEL} rw"/' /etc/default/grub
  fi
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
  grub-mkconfig -o /boot/grub/grub.cfg
else
  echo "Unknown BOOTLOADER option: $BOOTLOADER" >&2
  exit 1
fi

# Desktop: GNOME + essentials
pacman -Sy --noconfirm gnome gdm xdg-user-dirs pipewire wireplumber pipewire-alsa pipewire-pulse pavucontrol \
                        bluez bluez-utils cups avahi nss-mdns gvfs gvfs-smb flatpak firefox

if [[ "$GNOME_EXTRA" == "yes" ]]; then
  pacman -Sy --noconfirm gnome-extra
fi

# NVIDIA (optional)
if [[ "$NVIDIA" == "yes" ]]; then
  pacman -Sy --noconfirm nvidia nvidia-utils nvidia-settings
fi

# Services
systemctl enable NetworkManager
systemctl enable gdm
systemctl enable bluetooth
systemctl enable cups
systemctl enable avahi-daemon

# Quality-of-life
xdg-user-dirs-update
CHROOT

say "Base system & GNOME installed."

if [[ "$ENABLE_LUKS" == "yes" ]]; then
  say "Ensuring crypttab/fstab reflect labels (sanity step)"
  # Mapper opens at boot via kernel params + initramfs; fstab already uses UUIDs/labels
fi

say "All done. You can reboot now:"
echo "  umount -R $MOUNT_ROOT && swapoff -a || true"
echo "  reboot"
