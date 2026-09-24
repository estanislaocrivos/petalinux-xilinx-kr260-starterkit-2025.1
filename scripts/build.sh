#!/bin/bash
#
# Full PetaLinux build of the KR260 project.
#
# Usage: ./scripts/build.sh
#
# Outputs land in images/linux (BOOT.BIN, Image, system.dtb, rootfs, ...).
#

set -e

PETALINUX_SETTINGS=/opt/pkg/petalinux/2025.1/settings.sh
PROJECT_DIR="$(dirname "$(dirname "$(readlink -f "$0")")")"

cd "$PROJECT_DIR"

echo "*** Sourcing PetaLinux environment... ***"
source "$PETALINUX_SETTINGS"

echo "*** Building project... ***"
petalinux-build

echo "*** Packaging BOOT.BIN... ***"
petalinux-package --boot --u-boot --force

echo "*** Build complete: $PROJECT_DIR/images/linux ***"
