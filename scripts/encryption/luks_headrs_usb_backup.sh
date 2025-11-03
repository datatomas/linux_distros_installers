#!/bin/bash
# backup_nvme_headers.sh
# This script backs up NVMe disk headers and optionally writes them to a USB drive.

set -e  # Exit on error

# --- Step 1: Confirm devices ---
echo "Listing all block devices:"
lsblk
echo
echo "Make sure /dev/sda is your USB and will be overwritten if you proceed!"
read -p "Press ENTER to continue, or Ctrl+C to abort..."

# --- Step 2: Backup NVMe headers ---
echo "Backing up headers of NVMe drives..."
sudo dd if=/dev/nvme1n1 of=~/nvme1n1-header.img bs=1M count=1 status=progress
sudo dd if=/dev/nvme0n1 of=~/nvme0n1-header.img bs=1M count=1 status=progress
echo "Headers backed up to ~/nvme1n1-header.img and ~/nvme0n1-header.img"
echo

# --- Step 3: Write headers to USB ---
echo "WARNING: Writing headers to /dev/sda will overwrite its partition table!"
read -p "Type YES to continue: " confirm
if [ "$confirm" != "YES" ]; then
    echo "Aborted."
    exit 1
fi

# Choose which NVMe header to write
echo "Which header do you want to write to /dev/sda?"
echo "1) nvme1n1-header.img"
echo "2) nvme0n1-header.img"
read -p "Enter 1 or 2: " choice

if [ "$choice" == "1" ]; then
    sudo dd if=~/nvme1n1-header.img of=/dev/sda bs=1M count=1 status=progress
elif [ "$choice" == "2" ]; then
    sudo dd if=~/nvme0n1-header.img of=/dev/sda bs=1M count=1 status=progress
else
    echo "Invalid choice. Exiting."
    exit 1
fi

# --- Step 4: Refresh partition table ---
sudo partprobe /dev/sda
echo "Done! Current partitions on /dev/sda:"
lsblk /dev/sda
