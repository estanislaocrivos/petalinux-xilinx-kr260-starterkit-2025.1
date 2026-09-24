# AGENTS.md

PetaLinux 2025.1 project for the **Kria KR260 Robotics Starter Kit** (K26 SOM, SDT flow), used to run the
FreeRTOS/Baremetal R5 ↔ Linux A53 libmetal applications.

## Working rules

- **Do not run `petalinux-*` commands** (build, config, package). Hand the exact command to the user.
  Tools live in `/opt/pkg/petalinux/2025.1/settings.sh`.
- Editing files under `project-spec/meta-user` is fine.

## Boot chain

- Boot mode is **QSPI**. FSBL, PMUFW, TF-A and U-Boot come from the SOM QSPI (A/B slots), **not** from
  the SD card. The `BOOT.BIN` on the SD is ignored.
- The SD card sits behind the carrier USB hub (U-Boot sees it as `usb 0`, Linux as `/dev/sda`).
  U-Boot loads `boot.scr`, `Image` and `ramdisk.cpio.gz.u-boot` from `sda1`; the initramfs then
  switches root to the ext4 `sda2`.
- Any change to `BOOT.BIN` (FSBL, PMUFW, TF-A, U-Boot, the device tree embedded in it) requires
  a QSPI update from the running board:
  ```
  sudo xmutil bootfw_status
  sudo xmutil bootfw_update -i /run/media/sda1/BOOT.BIN   # writes the inactive slot
  sudo reboot                                              # check FSBL "Release 2025.1" on serial
  sudo xmutil bootfw_update -v                             # validate only if it booted fine
  ```
  Fallback: hold FWUEN at power-on → Image Recovery Tool at `192.168.0.111`.
- State as of 2026-09-23: **Image B** = this project's 2025.1 `BOOT.BIN` (validated, active);
  **Image A** = factory 2022.1 (fallback). The next `bootfw_update` overwrites Image A.
- Do **not** use the internal production QSPI procedure (`sf erase 0x0 0x3000000` + `sf write`):
  it wipes the Image Selector, A/B slots and Recovery Image of the starter kit layout.

## SD flashing

`./scripts/flash_sd.sh [device]` copies the boot files and extracts `rootfs.tar.gz` onto an SD already
partitioned as FAT32 (p1) + ext4 (p2). Serial console: `/dev/ttyUSB1`, 115200 8N1.

## R5 / libmetal integration

- R5_0 is started from Linux with **remoteproc** (after Linux boots); no R5 partition in `BOOT.BIN`.
- `project-spec/meta-user/recipes-bsp/device-tree/files/system-user.dtsi` is ported from the
  custom-board project `mimo_k26` (`~/repositories/rt-rnd/freertos-libmetal-echo/petalinux/mimo_k26`),
  keeping only the AMP nodes:
  - reserved memory: R5 firmware 1 MB @ `0x3ed00000`, shared memory 1 MB @ `0x3ee00000`
  - `rf5ss@ff9a0000` (`xlnx,zynqmp-r5fss`, split mode, R5_0 with TCM A/B)
  - `shm_uio` (generic-uio over the shared memory)
  - `ipi_amp` (generic-uio over `psu_ipi_2` @ `0xff320000`, SPI 34)
- **TTC0 drives the fan PWM on the KR260** (`pwm-fan` in `zynqmp-sm-k26-reva.dtsi`) and must stay
  enabled. The FreeRTOS tick uses **TTC1** (`0xff120000`), disabled for Linux in `system-user.dtsi`.
  The R5 firmware BSP still has to be retargeted from TTC0 to TTC1 (`configTIMER_*` in
  `FreeRTOSConfig.h`).
- The XSA does not need regenerating: TTC0–TTC3 are already enabled in the starter kit design.
- Kernel already provides `UIO`, `UIO_PDRV_GENIRQ` (module) and `XLNX_R5_REMOTEPROC`.
  `uio_pdrv_genirq` must be loaded before `bind-uio.sh` runs.

- CMA is reduced to **512 MB** (`CONFIG_SUBSYSTEM_EXTRA_BOOTARGS`). With `cma=900M` the R5 reserved
  regions split low DDR and no 900 MB contiguous hole was left: CMA failed, the FPGA manager could
  not load the base bitstream and the fan (TTC0 PWM routed through the PL) ran at full speed.

## Pending

- Compare remaining config from `mimo_k26` (kernel fragments, `CONFIG_SUBSYSTEM_USER_CMDLINE`,
  rootfs packages, custom `meta-user` recipes) and port only what is not board-specific.
- Retarget the FreeRTOS tick to TTC1 and rebuild the R5 firmware.
- Bind the `generic-uio` nodes at boot: prefer `/etc/modules-load.d/` (load `uio_pdrv_genirq`) +
  `/etc/modprobe.d/` (`options uio_pdrv_genirq of_id=generic-uio`) over `bind-uio.sh`.
