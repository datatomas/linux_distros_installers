
set -euo pipefail

DATA_PART=/dev/nvme0n1p4
MAPPER=data_crypt
MOUNT=/data

echo "== Stop users of $MOUNT and unmount"
sudo lsof +f -- "$MOUNT" || true
# sudo systemctl stop docker postgresql mongod minio || true
sudo umount "$MOUNT"

echo "== Filesystem check"
sudo e2fsck -f "$DATA_PART"
# 1) sanity check & unmount
sudo lsof +f -- /data || true
sudo umount /data

# 2) check FS
sudo e2fsck -f /dev/nvme0n1p4

# 3) shrink ext4 slightly (leave ~128–256 MiB slack)
# pick one:

# (A) 256 MiB slack (extra safe)
SZ=$(sudo blockdev --getsize64 /dev/nvme0n1p4); TGT=$((SZ/1024/1024 - 256))
sudo resize2fs /dev/nvme0n1p4 ${TGT}M

# or (B) 128 MiB slack if you prefer
# SZ=$(sudo blockdev --getsize64 /dev/nvme0n1p4); TGT=$((SZ/1024/1024 - 128))
# sudo resize2fs /dev/nvme0n1p4 ${TGT}M

# 4) in-place encrypt (match reduce to be <= your slack)
sudo cryptsetup reencrypt --encrypt --type luks2 --reduce-device-size 32M /dev/nvme0n1p4

# 5) open, grow back, and mount
sudo cryptsetup open /dev/nvme0n1p4 data_crypt
sudo resize2fs /dev/mapper/data_crypt
sudo mount /dev/mapper/data_crypt /data
