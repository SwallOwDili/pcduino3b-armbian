#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

display_alert() {
	:
}

run_host_command_logged() {
	CONFIG_CALLS+=("$*")
}

# shellcheck source=../userpatches/config/boards/pcduino3b.csc
source "$REPO_ROOT/userpatches/config/boards/pcduino3b.csc"

assert_profile() {
	local profile=$1
	local target_number=$2
	local expect_nand=$3
	CONFIG_CALLS=()
	BOARD=pcduino3b
	PCDUINO3B_IMAGE_PROFILE=$profile
	uboot_target_counter=$target_number
	post_config_uboot_target__extra_configs_for_pcduino3b

	[[ "${CONFIG_CALLS[0]}" == 'scripts/config --set-val CONFIG_DRAM_CLK 408' ]]
	[[ "${CONFIG_CALLS[1]}" == 'scripts/config --set-str CONFIG_DEFAULT_DEVICE_TREE sun7i-a20-pcduino3b' ]]
	[[ "${CONFIG_CALLS[2]}" == 'scripts/config --set-str CONFIG_OF_LIST sun7i-a20-pcduino3b' ]]
	if [[ "$expect_nand" == yes ]]; then
		for expected in \
			'scripts/config --enable CONFIG_MTD_RAW_NAND' \
			'scripts/config --enable CONFIG_NAND_SUNXI' \
			'scripts/config --enable CONFIG_CMD_NAND' \
			'scripts/config --disable CONFIG_CMD_UBI' \
			'scripts/config --disable CONFIG_CMD_UBIFS' \
			'scripts/config --enable CONFIG_FIT' \
			'scripts/config --enable CONFIG_FIT_FULL_CHECK' \
			'scripts/config --enable CONFIG_SHA256' \
			'scripts/config --enable CONFIG_CMD_BOOTM' \
			'scripts/config --set-val CONFIG_SYS_BOOTM_LEN 0x04000000' \
			'scripts/config --set-val CONFIG_NAND_SUNXI_SPL_ECC_STRENGTH 64' \
			'scripts/config --set-val CONFIG_SYS_NAND_PAGE_SIZE 0x2000' \
			'scripts/config --set-val CONFIG_SYS_NAND_OOBSIZE 0x280' \
			'scripts/config --set-val CONFIG_SYS_NAND_U_BOOT_OFFS 0x800000'; do
			printf '%s\n' "${CONFIG_CALLS[@]}" | grep -Fxq "$expected"
		done
	elif [[ "$profile" == nand-* ]]; then
		for expected in \
			'scripts/config --disable CONFIG_MTD_RAW_NAND' \
			'scripts/config --disable CONFIG_NAND_SUNXI' \
			'scripts/config --disable CONFIG_CMD_NAND' \
			'scripts/config --disable CONFIG_SPL_NAND_SUPPORT'; do
			printf '%s\n' "${CONFIG_CALLS[@]}" | grep -Fxq "$expected"
		done
	else
		[[ ${#CONFIG_CALLS[@]} -eq 3 ]]
	fi
}

assert_profile dev 1 no
assert_profile sd-release 1 no
assert_profile nand-installer 1 no
assert_profile nand-installer 2 yes
assert_profile nand-recovery 1 no
assert_profile nand-recovery 2 yes

WORKFLOW="$REPO_ROOT/.github/workflows/image-build.yml"
grep -Fq 'if sudo grep -Eq "^${option}=y$" "${sd_uboot_configs[0]}"; then' "$WORKFLOW"
if grep -Fq 'grep -Fxq "# $option is not set" "${sd_uboot_configs[0]}"' "$WORKFLOW"; then
	echo 'SD U-Boot acceptance incorrectly requires disabled Kconfig symbols to be emitted' >&2
	exit 1
fi

UBOOT_PATCH="$REPO_ROOT/userpatches/u-boot/v2026.07-sunxi/board_pcduino3b/0001-pcduino3b-enable-onboard-nand.patch"
for expected in \
	'sun7i-a20-pcduino3b.dts' \
	'model = "LinkSprite pcDuino3B";' \
	'phy-mode = "rgmii-id";' \
	'pcduino3b_nand_pins: nand-pins' \
	'int max_oobsize;' \
	'if (ecc_bytes[ecc_idx] * nsectors + total_user_data_sz >' \
	'    max_oobsize)' \
	'label = "spl-primary";' \
	'label = "spl-backup";' \
	'label = "uboot";' \
	'label = "bootfit";' \
	'label = "rootfs";' \
	'reg = <0x02000000 0x06000000>;' \
	'reg = <0x08000000 0xf8000000>;'; do
	grep -Fq "$expected" "$UBOOT_PATCH"
done
if grep -Eq '^[ +][[:space:]]*if \(ecc_bytes\[ecc_idx\] \+ total_user_data_sz > max_ecc_bytes\)' \
	"$UBOOT_PATCH"; then
	echo 'pcDuino3B U-Boot patch retains the v2026.07 SPL ECC unit mismatch' >&2
	exit 1
fi

# Model the fixed v2026.07 SPL probe for this board's 8 KiB page,
# 640-byte OOB, 1 KiB ECC step and 4 user bytes per step. Index 4 is
# 40-bit ECC; index 5 is 48-bit and must not fit.
ecc_bytes=(28 42 50 56 70 84 98 106 112)
ecc_strengths=(16 24 28 32 40 48 56 60 64)
nsectors=$((8192 / 1024))
total_user_data_sz=$((nsectors * 4))
max_oobsize=640
max_ecc_idx=-1
for ecc_idx in "${!ecc_bytes[@]}"; do
	if ((ecc_bytes[ecc_idx] * nsectors + total_user_data_sz > max_oobsize)); then
		break
	fi
	max_ecc_idx=$ecc_idx
done
[[ "$max_ecc_idx" -ge 0 ]]
[[ "${ecc_strengths[max_ecc_idx]}" -eq 40 ]]
[[ $((ecc_bytes[max_ecc_idx] * nsectors + total_user_data_sz)) -eq 592 ]]
[[ $((ecc_bytes[max_ecc_idx + 1] * nsectors + total_user_data_sz)) -eq 704 ]]
if grep -Fq 'func(UBIFS' "$UBOOT_PATCH"; then
	echo 'pcDuino3B U-Boot must not read the SLC-emulated rootfs UBI' >&2
	exit 1
fi
if grep -Fq 'diff --git a/arch/arm/dts/sun7i-a20-pcduino3.dts' "$UBOOT_PATCH"; then
	echo 'pcDuino3B U-Boot patch modifies the upstream pcDuino3 DTS' >&2
	exit 1
fi

LAYOUT="$REPO_ROOT/userpatches/overlay/usr/share/pcduino3b/nand-layout.env"
# shellcheck disable=SC1090
source "$LAYOUT"
[[ "$PCDUINO3B_NAND_TOTAL_BYTES" -eq 4294967296 ]]
[[ "$PCDUINO3B_NAND_UBOOT_OFFSET" -eq 8388608 ]]
[[ "$PCDUINO3B_NAND_BOOTFIT_OFFSET" -eq 33554432 ]]
[[ "$PCDUINO3B_NAND_ROOTFS_OFFSET" -eq 134217728 ]]
[[ $((PCDUINO3B_NAND_ROOTFS_OFFSET + PCDUINO3B_NAND_ROOTFS_PHYSICAL_BYTES)) \
	-eq "$PCDUINO3B_NAND_TOTAL_BYTES" ]]
[[ "$PCDUINO3B_NAND_ROOTFS_LOGICAL_BYTES" \
	-eq $((PCDUINO3B_NAND_ROOTFS_PHYSICAL_BYTES / 2)) ]]
[[ "$PCDUINO3B_NAND_ROOTFS_LEB_BYTES" \
	-eq $((PCDUINO3B_NAND_ROOTFS_PEB_BYTES - PCDUINO3B_NAND_ROOTFS_DATA_OFFSET)) ]]
printf '%s\n' "${CONFIG_CALLS[@]}" \
	| grep -Fq 'if nand read 0x50000000 0x02000000 0x04000000; then bootm 0x50000000; fi'
printf '%s\n' "${CONFIG_CALLS[@]}" \
	| grep -Fq "CONFIG_BOOTCOMMAND 'run distro_bootcmd;"
if printf '%s\n' "${CONFIG_CALLS[@]}" | grep -Fq '&&'; then
	echo 'CONFIG_BOOTCOMMAND contains an ampersand that scripts/config would expand' >&2
	exit 1
fi

echo 'pcduino3b NAND U-Boot config fixture: PASS'
