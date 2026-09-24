#!/bin/bash
#
# Flash PetaLinux build artifacts to the KR260 SD card.
#
# Usage: ./scripts/flash_sd.sh [device]
#        ./scripts/flash_sd.sh           # defaults to /dev/mmcblk0
#        ./scripts/flash_sd.sh /dev/sdb  # USB card reader
#
# Expects an SD card already partitioned as:
#   p1 -> FAT32, boot partition
#   p2 -> ext4,  root filesystem
#

set -e

DEVICE="${1:-/dev/mmcblk0}"
PROJECT_DIR="$(dirname "$(dirname "$(readlink -f "$0")")")"
IMAGES="$PROJECT_DIR/images/linux"

BOOT_MNT=/mnt/boot
ROOTFS_MNT=/mnt/rootfs

# Must match IMAGE_BOOT_FILES in project-spec/meta-user/conf/petalinuxbsp.conf
BOOT_FILES="BOOT.BIN boot.scr Image ramdisk.cpio.gz.u-boot"
BOOT_FILES_OPTIONAL="system.dtb system-zynqmp-sck-kr-g-revB.dtb"

# Partition naming differs between mmcblk0p1 and sdb1
if [[ "$DEVICE" =~ (mmcblk|nvme|loop)[0-9]+$ ]]; then
	BOOT_PART="${DEVICE}p1"
	ROOTFS_PART="${DEVICE}p2"
else
	BOOT_PART="${DEVICE}1"
	ROOTFS_PART="${DEVICE}2"
fi

cleanup() {
	# Never leave partitions mounted if something fails mid-flash
	mountpoint -q "$ROOTFS_MNT" && sudo umount "$ROOTFS_MNT" || true
	mountpoint -q "$BOOT_MNT" && sudo umount "$BOOT_MNT" || true
}
trap cleanup EXIT

echo "*** Checking target device... ***"
ROOT_DISK=$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" 2>/dev/null || true)
if [ "$DEVICE" = "/dev/$ROOT_DISK" ]; then
	echo "REFUSING: $DEVICE is the system disk." >&2
	exit 1
fi
[ -b "$BOOT_PART" ] || { echo "ERROR: $BOOT_PART not found." >&2; exit 1; }
[ -b "$ROOTFS_PART" ] || { echo "ERROR: $ROOTFS_PART not found." >&2; exit 1; }

lsblk -o NAME,SIZE,FSTYPE,LABEL "$DEVICE"
read -rp "Erase and flash $DEVICE? [y/N] " answer
[ "$answer" = "y" ] || { echo "Aborted."; exit 1; }

echo "*** Checking build artifacts... ***"
for f in $BOOT_FILES rootfs.tar.gz; do
	[ -f "$IMAGES/$f" ] || { echo "ERROR: missing $IMAGES/$f" >&2; exit 1; }
done

echo "*** Unmounting automounted partitions... ***"
# The desktop automounts the card under /media; it must be released first
for part in "$BOOT_PART" "$ROOTFS_PART"; do
	findmnt -no TARGET "$part" | while read -r mp; do
		echo "    releasing $part from $mp"
		sudo umount "$part"
	done
done

echo "*** Mounting partitions... ***"
sudo mkdir -p "$BOOT_MNT" "$ROOTFS_MNT"
sudo mount "$ROOTFS_PART" "$ROOTFS_MNT"
sudo mount "$BOOT_PART" "$BOOT_MNT"

echo "*** Cleaning up partitions... ***"
# Guarded: without the mountpoint check this would wipe the local /mnt dirs
mountpoint -q "$ROOTFS_MNT" || { echo "ERROR: $ROOTFS_MNT not mounted." >&2; exit 1; }
mountpoint -q "$BOOT_MNT" || { echo "ERROR: $BOOT_MNT not mounted." >&2; exit 1; }
sudo rm -rf "${ROOTFS_MNT:?}"/*
sudo rm -rf "${BOOT_MNT:?}"/*

echo "*** Flashing boot partition... ***"
for f in $BOOT_FILES; do
	echo "    $f"
	sudo cp "$IMAGES/$f" "$BOOT_MNT/"
done
for f in $BOOT_FILES_OPTIONAL; do
	if [ -f "$IMAGES/$f" ]; then
		echo "    $f (optional)"
		sudo cp -L "$IMAGES/$f" "$BOOT_MNT/"
	fi
done

echo "*** Flashing root filesystem... ***"
# -p preserves the permissions the rootfs was built with; ownership is kept
# because tar runs as root. Dropping either breaks sudo, ssh and systemd.
sudo tar -xpzf "$IMAGES/rootfs.tar.gz" -C "$ROOTFS_MNT/"

echo "*** Syncing... ***"
sync

echo "*** Unmounting partitions... ***"
sudo umount "$BOOT_MNT"
sudo umount "$ROOTFS_MNT"

echo "*** Flash complete ***"
