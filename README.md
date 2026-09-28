# Xilinx Kria KR260 PetaLinux 2025.1 Project

PetaLinux 2025.1 project for the Kria **KR260 Robotics Starter Kit** (K26 SOM), based on the official
AMD BSP. It runs Linux on the A53 cluster and leaves **R5_0/1** free for FreeRTOS/baremetal firmware
that talks to Linux through libmetal (shared memory + IPI).

## What differs from the stock BSP

- **AMP device tree** (`project-spec/meta-user/recipes-bsp/device-tree/files/system-user.dtsi`):
  - reserved DDR for R5_0: firmware @ `0x3ed00000`, shared memory @ `0x3ee00000` (1 MB each)
  - `rf5ss` node so Linux can load and start R5_0 with `remoteproc`
  - `generic-uio` nodes for the shared memory and the IPI channel (`0xff320000`, SPI 34)
  - TTC0 and `pwm-fan` disabled for Linux: TTC0 is the FreeRTOS tick, so the fan runs at full speed
- **CMA reduced to 512 MB** (`cma=512M`), so it still fits in low DDR next to the R5 regions.

## Layout

```text
project-spec/   PetaLinux configuration, meta-user layer and hardware description
hardware/       Vivado base design (XSA) and its SDT
scripts/        build.sh (full build), flash_sd.sh (copy images to the SD card)
BUILD.md        host setup and build notes
AGENTS.md       project notes for AI agents (boot chain, QSPI state, R5 integration)
```

## Build and flash

```sh
./scripts/build.sh             # outputs in images/linux
./scripts/flash_sd.sh /dev/sdX # SD pre-partitioned as FAT32 (p1) + ext4 (p2)
```

Serial console: `/dev/ttyUSB1`, 115200 8N1.

## Boot firmware

The KR260 boots from **QSPI**: FSBL, PMUFW, TF-A and U-Boot come from the SOM, not from the SD card.
After changing anything that ends up in `BOOT.BIN`, update the QSPI from the running board:

```sh
sudo xmutil bootfw_update -i /run/media/sda1/BOOT.BIN
sudo reboot
sudo xmutil bootfw_update -v # only after it booted fine
```

## References

- UG1089 / UG1092: KR260 Starter Kit and carrier card user guides
- UG1144: PetaLinux Tools Reference Guide
- UG1085: Zynq UltraScale+ Technical Reference Manual
- UG1186: OpenAMP / libmetal User Guide
