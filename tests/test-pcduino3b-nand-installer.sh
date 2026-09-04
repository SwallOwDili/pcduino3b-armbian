#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="$REPO_ROOT/userpatches/overlay/usr/local/sbin/pcduino3b-nand-install"
LAYOUT="$REPO_ROOT/userpatches/overlay/usr/share/pcduino3b/nand-layout.env"
OVERLAY="$REPO_ROOT/userpatches/dts/sun7i-a20-pcduino3b-nand-layout.dtso"

bash -n "$INSTALLER"

for guard in \
	'installer must run from microSD' \
	'image profile' \
	'partition offset' \
	'NAND controller' \
	'MTD character device is missing' \
	'UBI control device is missing' \
	'ECC strength' \
	'ECC step size' \
	'rootfs MTD type' \
	'invalid bad-block count' \
	'is not writable; refusing before erase' \
	'boot-region bad-block count' \
	'raw MLC NAND without SLC emulation; refusing before erase' \
	'payload installer does not match the running NAND installer' \
	'required SHA256SUMS entry count' \
	'sha256sum -c SHA256SUMS' \
	'host backup SHA-256' \
	'--host-backup-confirmed is required' \
	'another pcduino3b NAND installer is already running' \
	'installer lock directory is a symlink' \
	'no later NAND phase will run' \
	'ERASE-PCDUINO3B-NAND-$PCDUINO3B_NAND_ID' \
	'INSTALL_STATUS=PASS'; do
	grep -Fq -- "$guard" "$INSTALLER"
done

plan_exit_line=$(grep -n "NAND_WRITE=NOT_REQUESTED" "$INSTALLER" | cut -d: -f1)
first_write_line=$(grep -nE '^[[:space:]]*(ubiformat|flash_erase|nandwrite)[[:space:]]' \
	"$INSTALLER" | head -n1 | cut -d: -f1)
[[ -n "$plan_exit_line" && -n "$first_write_line" ]]
((plan_exit_line < first_write_line))

mlc_guard_line=$(grep -n 'raw MLC NAND without SLC emulation; refusing before erase' \
	"$INSTALLER" | cut -d: -f1)
[[ -n "$mlc_guard_line" ]]
((mlc_guard_line < first_write_line))
grep -Fq 'expect_value "$ROOTFS_TYPE" mlc-nand' "$INSTALLER"
grep -Fq '((ROOTFS_FLAGS & 0x4000))' "$INSTALLER"
grep -Fq '((DEVICE_FLAGS & 0x400))' "$INSTALLER"
grep -Fq '[[ "$value" =~ ^[0-9]+$ ]]' "$INSTALLER"
grep -Fq '[[ "$value" =~ ^0x[0-9a-fA-F]+$ ]]' "$INSTALLER"
grep -Fq '[[ "${path##*/}" =~ ^mtd[0-9]+$ ]]' "$INSTALLER"
grep -Fq 'pcduino3b-nand-boot.itb' "$INSTALLER"
grep -Fq 'dumpimage -l "$BOOTFIT_IMAGE"' "$INSTALLER"
grep -Fq 'readlink -f "${BASH_SOURCE[0]}"' "$INSTALLER"
grep -Fq 'cmp -s "$RUNNING_INSTALLER" "$PAYLOAD_INSTALLER"' "$INSTALLER"
grep -Fq 'checksum_entry_count' "$INSTALLER"
grep -Fq 'LOCK_DIR=/run/pcduino3b' "$INSTALLER"
grep -Fq 'rm -f -- "$MOUNT_DIR/boot.itb"' "$INSTALLER"
grep -Fq '[[ -c /dev/ubi_ctrl ]]' "$INSTALLER"
grep -Fq '[[ "${ubi_path##*/}" =~ ^ubi[0-9]+$ ]]' "$INSTALLER"
bad_block_validation_line=$(grep -n 'BOOTFIT_BAD_BLOCKS="$(bad_block_count' \
	"$INSTALLER" | cut -d: -f1)
bad_block_arithmetic_line=$(grep -n 'BOOTFIT_USABLE_BYTES=' "$INSTALLER" | cut -d: -f1)
self_match_line=$(grep -n 'cmp -s "$RUNNING_INSTALLER" "$PAYLOAD_INSTALLER"' \
	"$INSTALLER" | cut -d: -f1)
checksum_count_line=$(grep -n 'for required_name in' "$INSTALLER" | cut -d: -f1)
[[ -n "$bad_block_validation_line" && -n "$bad_block_arithmetic_line" ]]
[[ -n "$self_match_line" && -n "$checksum_count_line" ]]
((bad_block_validation_line < bad_block_arithmetic_line))
((self_match_line < first_write_line))
((checksum_count_line < first_write_line))

checksum_guard=$(sed -n '/^for required_name in/,/^done$/p' "$INSTALLER")
for required_name in \
	pcduino3b-nand-rootfs.ubi \
	pcduino3b-nand-boot.itb \
	pcduino3b-nand-spl-with-ecc.bin \
	pcduino3b-nand-u-boot.bin \
	pcduino3b-nand-layout.env \
	pcduino3b-nand-layout.dtbo \
	pcduino3b-nand-install \
	pcduino3b-nand-manifest.txt; do
	grep -Fq "$required_name" <<<"$checksum_guard"
done
grep -Fq "trap 'abort_on_signal SIGINT 130' INT" "$INSTALLER"
grep -Fq "trap 'abort_on_signal SIGTERM 143' TERM" "$INSTALLER"
if grep -Fq 'trap cleanup EXIT INT TERM' "$INSTALLER"; then
	echo 'signal traps must exit instead of returning to a later write phase' >&2
	exit 1
fi

if grep -Eq '(^|[[:space:]])(nand erase\.chip|flash_erase /dev/mtd0|nandwrite[^\n]*/dev/mtd0)' \
	"$INSTALLER"; then
	echo 'installer contains an unpartitioned whole-device write' >&2
	exit 1
fi

# shellcheck disable=SC1090
source "$LAYOUT"
[[ "$PCDUINO3B_NAND_ID" == add794916044 ]]
[[ "$PCDUINO3B_NAND_BASELINE_BACKUP_BYTES" -eq 4630511616 ]]
[[ ${#PCDUINO3B_NAND_BASELINE_BACKUP_SHA256} -eq 64 ]]
[[ $((PCDUINO3B_NAND_SPL_REGION_BYTES * 2)) \
	-eq "$PCDUINO3B_NAND_UBOOT_OFFSET" ]]
[[ $((PCDUINO3B_NAND_UBOOT_OFFSET + PCDUINO3B_NAND_UBOOT_REGION_BYTES)) \
	-eq "$PCDUINO3B_NAND_BOOTFIT_OFFSET" ]]
[[ $((PCDUINO3B_NAND_BOOTFIT_OFFSET + PCDUINO3B_NAND_BOOTFIT_REGION_BYTES)) \
	-eq "$PCDUINO3B_NAND_ROOTFS_OFFSET" ]]
[[ $((PCDUINO3B_NAND_ROOTFS_OFFSET + PCDUINO3B_NAND_ROOTFS_PHYSICAL_BYTES)) \
	-eq "$PCDUINO3B_NAND_TOTAL_BYTES" ]]
[[ "$PCDUINO3B_NAND_ROOTFS_LOGICAL_BYTES" \
	-eq $((PCDUINO3B_NAND_ROOTFS_PHYSICAL_BYTES / 2)) ]]

for label in spl-primary spl-backup uboot bootfit rootfs; do
	grep -Fq "label = \"$label\";" "$OVERLAY"
done
grep -Fq 'reg = <0x02000000 0x06000000>;' "$OVERLAY"
grep -Fq 'reg = <0x08000000 0xf8000000>;' "$OVERLAY"
grep -Fq 'slc-mode;' "$OVERLAY"

rootfs_write_line=$(grep -n "PHASE=write-ubi-rootfs" "$INSTALLER" | cut -d: -f1)
bootfit_write_line=$(grep -n "PHASE=write-boot-fit" "$INSTALLER" | cut -d: -f1)
backup_spl_line=$(grep -n "PHASE=write-backup-spl" "$INSTALLER" | cut -d: -f1)
uboot_write_line=$(grep -n "PHASE=write-uboot" "$INSTALLER" | cut -d: -f1)
primary_spl_line=$(grep -n "PHASE=write-primary-spl" "$INSTALLER" | cut -d: -f1)
((rootfs_write_line < bootfit_write_line))
((bootfit_write_line < backup_spl_line))
((backup_spl_line < uboot_write_line))
((uboot_write_line < primary_spl_line))

echo 'pcduino3b NAND installer safety fixture: PASS'
