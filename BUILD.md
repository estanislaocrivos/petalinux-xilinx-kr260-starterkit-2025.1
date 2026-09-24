# Kria KR260 PetaLinux 2025.1 — Build Notes

Custom rootfs for the AMD Kria KR260 Starter Kit, built from the official BSP.

|                |                                                                           |
| -------------- | ------------------------------------------------------------------------- |
| Target         | Kria KR260 Starter Kit (K26 SOM, `XCK26-SFVC784`, Zynq UltraScale+ MPSoC) |
| Project        | `xilinx-kr260-starterkit-2025.1` (created from the official BSP)          |
| Host           | Ubuntu 24.04.5 LTS                                                        |
| Vivado / Vitis | `/opt/Xilinx/2025.1` (Vivado ML Enterprise, root-owned)                   |
| PetaLinux      | `/opt/pkg/petalinux/2025.1` (user-owned)                                  |
| sstate cache   | `/opt/pkg/petalinux/sstate-2025.1/aarch64`                                |

The `XCK26` belongs to the `zynquplus` device family, which ships with the
default Vivado install — no extra device families are required. Kria board
files are bundled too, under
`/opt/Xilinx/2025.1/data/xhub/boards/XilinxBoardStore/boards/Xilinx/kr260_*`.

## Host setup

Two host-side issues had to be resolved before anything would build.

### 1. Unprivileged user namespaces (mandatory)

Ubuntu 24.04 restricts unprivileged user namespaces through AppArmor. BitBake
needs them for `pseudo`, and fails with:

```text
ERROR: User namespaces are not usable by BitBake, possibly due to AppArmor.
```

Fix, persisted in `/etc/sysctl.d/99-bitbake-userns.conf`:

```bash
echo "kernel.apparmor_restrict_unprivileged_userns=0" | sudo tee /etc/sysctl.d/99-bitbake-userns.conf
sudo sysctl --system
```

Files under `/etc/sysctl.d/` are only read at boot, so `sysctl --system` (or
`sysctl -w`) is required to apply the value without rebooting. Verify with:

```bash
sysctl kernel.apparmor_restrict_unprivileged_userns # must print 0
unshare --user --map-root-user echo "userns OK"
```

This disables the restriction system-wide. Acceptable on a single-user
development workstation; reconsider on a shared or exposed machine.

### 2. Host packages

On top of a stock Ubuntu 24.04:

```bash
sudo dpkg --add-architecture i386 && sudo apt update
sudo apt install -y gcc-multilib zlib1g:i386 screen pax socat flex bison \
    diffstat chrpath python3-git python3-subunit lz4
```

`libncurses5-dev` and `liblz4-tool` listed in UG1144 are transitional packages
that no longer exist on noble; `libncurses-dev` and `lz4` replace them.

## Project creation

```bash
source /opt/pkg/petalinux/2025.1/settings.sh
cd ~/petalinux-workspace
petalinux-create project -s ~/Downloads/xilinx-kr260-starterkit-v2025.1-final.bsp
cd xilinx-kr260-starterkit-2025.1
```

Starting from the BSP rather than `--template zynqMP` is what provides the
KR260 device tree, boot configuration and SOM firmware wiring.

> Never source the Vivado and PetaLinux environments in the same shell. Both
> overwrite `PATH` and `LD_LIBRARY_PATH`; PetaLinux ships its own toolchain and
> layering Vivado on top breaks builds in ways that are hard to trace.

## Key configuration

### sstate cache

`project-spec/configs/config`:

```text
CONFIG_YOCTO_LOCAL_SSTATE_FEEDS_URL="/opt/pkg/petalinux/sstate-2025.1/aarch64"
CONFIG_YOCTO_NETWORK_SSTATE_FEEDS=y
```

Set via `petalinux-config` → *Yocto Settings* → *Local sstate feeds settings*.
The cache lives **outside** the project directory so it survives
`petalinux-build -x cleanall` and is shared across projects. Without it the
first build takes 4–6 hours instead of ~40 minutes.

### FPGA overlays (required for this board)

`project-spec/meta-user/conf/petalinuxbsp.conf`:

```text
MACHINE_FEATURES = "vcu"
MACHINE_FEATURES:append = " fpga-overlay"
```

The BSP ships line 16 with an absolute `=` assignment that omits
`fpga-overlay`, which produces:

```text
WARNING: k26-starter-kits do_configure: Using dfx_user_dts.bbclass
         requires fpga-overlay MACHINE_FEATURE to be enabled
```

Without this feature the build still succeeds, but `xmutil loadapp` cannot
load FPGA overlays on the board — which is how the KR260 receives the
bitstream. The `:append` form is used so it survives a BSP update overwriting
the `=` line.

### Boot files

`project-spec/meta-user/conf/petalinuxbsp.conf`:

```text
IMAGE_BOOT_FILES:zynqmp = "BOOT.BIN boot.scr Image ramdisk.cpio.gz.u-boot "
```

### Root filesystem

```text
CONFIG_SUBSYSTEM_ROOTFS_INITRD=y
CONFIG_SUBSYSTEM_INITRAMFS_IMAGE_NAME="petalinux-initramfs-image"
```

This is the BSP default and is correct for Kria: U-Boot loads `Image` plus the
initramfs, and the initramfs then switches to the real root filesystem on SD
partition 2. The `rootfs.ext4` / `rootfs.tar.gz` artifacts are that root
filesystem — `INITRD` here does *not* mean the system runs from RAM.

### Custom rootfs content

| Goal                           | Where                                                          |
| ------------------------------ | -------------------------------------------------------------- |
| Enable existing Yocto packages | `petalinux-config -c rootfs`                                   |
| Declare packages as a list     | `project-spec/meta-user/conf/user-rootfsconfig`                |
| Own applications               | `petalinux-create apps --template install --name <n> --enable` |
| Kernel modules                 | `petalinux-create modules --name <n> --enable`                 |

Recipes land under `project-spec/meta-user/recipes-apps/` and
`recipes-modules/`. This project carries `recipes-modules/my-driver/`.

## Build

```bash
source /opt/pkg/petalinux/2025.1/settings.sh
cd ~/petalinux-workspace/xilinx-kr260-starterkit-2025.1

petalinux-build                         # full build
petalinux-build -c <recipe>             # single recipe (optional)
petalinux-build -x cleanall -c <recipe> # force a recipe rebuild (optional)

petalinux-package boot --u-boot --force # produces BOOT.BIN
petalinux-package wic                   # produces a full SD image
```

`petalinux-package wic` needs no arguments — it reads `IMAGE_BOOT_FILES` from
the BSP config.

Artifacts land in `images/linux/`:

| File                              |                                                        |
| --------------------------------- | ------------------------------------------------------ |
| `BOOT.BIN`                        | FSBL + PMUFW + ATF + U-Boot                            |
| `Image`                           | kernel                                                 |
| `boot.scr`                        | U-Boot boot script                                     |
| `ramdisk.cpio.gz.u-boot`          | initramfs                                              |
| `system.dtb`                      | symlink to `system-zynqmp-sck-kr-g-revB.dtb`           |
| `rootfs.tar.gz`                   | root filesystem, for partition-level flashing          |
| `rootfs.ext4`                     | root filesystem image, used by `petalinux-package wic` |
| `dtbos/zynqmp-sck-kr-g-revB.dtbo` | carrier card device tree overlay                       |

## Flashing

`./scripts/flash_sd.sh [device]` writes the artifacts to an SD card already partitioned as
p1 = FAT32 (boot) and p2 = ext4 (root). Defaults to `/dev/mmcblk0`.

```bash
./scripts/flash_sd.sh          # built-in card reader
./scripts/flash_sd.sh /dev/sdb # USB card reader
```

The script refuses to touch the system disk, checks that every required
artifact exists before erasing anything, releases the desktop automount under
`/media`, and verifies the mounts succeeded before running `rm -rf`.

The root filesystem is extracted with `sudo tar -xpzf`, preserving ownership
and permissions. Extracting with `--no-same-owner` breaks `sudo`, SSH host keys
and several systemd units.

Alternatively, `petalinux-package wic` produces a single `.wic` image to be
written with `dd` or `bmaptool` — simpler, but it rewrites the whole card on
every iteration.

## Board notes

**QSPI boot firmware.** The K26 SOM holds boot firmware in QSPI, independent of
the SD card. If `BOOT.BIN` is newer than the SOM firmware the board may not
boot. Boot the stock AMD image once, check the version, and update with
`xmutil bootfw_update` if needed before flashing a custom image.

**FPGA overlays.** The PL design is not loaded from `BOOT.BIN`. It is deployed
as an overlay — `.bit.bin` + `.dtbo` + `shell.json` copied to
`/lib/firmware/xilinx/<app>/` over the network, then:

```bash
sudo xmutil unloadapp
sudo xmutil loadapp <app>
```

A custom rootfs must therefore keep `xmutil` and `fpga-manager` installed. They
come with the BSP, but a heavily trimmed rootfs can drop them silently.

## References

- UG1144 — PetaLinux Tools Reference Guide
- UG1089 — Kria SOM Starter Kit Applications
- <https://xilinx.github.io/kria-apps-docs/>
