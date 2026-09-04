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
	local expect_nand=$2
	CONFIG_CALLS=()
	BOARD=pcduino3b
	PCDUINO3B_IMAGE_PROFILE=$profile
	post_config_uboot_target__extra_configs_for_pcduino3b

	[[ "${CONFIG_CALLS[0]}" == 'scripts/config --set-val CONFIG_DRAM_CLK 408' ]]
	[[ "${CONFIG_CALLS[1]}" == 'scripts/config --set-str CONFIG_DEFAULT_DEVICE_TREE sun7i-a20-pcduino3b' ]]
	[[ "${CONFIG_CALLS[2]}" == 'scripts/config --set-str CONFIG_OF_LIST sun7i-a20-pcduino3b' ]]
	if [[ "$expect_nand" == yes ]]; then
		for expected in \
			'scripts/config --enable CONFIG_MTD_RAW_NAND' \
			'scripts/config --enable CONFIG_NAND_SUNXI' \
			'scripts/config --enable CONFIG_CMD_NAND' \
			'scripts/config --enable CONFIG_CMD_UBI' \
			'scripts/config --enable CONFIG_CMD_UBIFS' \
			'scripts/config --set-val CONFIG_NAND_SUNXI_SPL_ECC_STRENGTH 64' \
			'scripts/config --set-val CONFIG_SYS_NAND_PAGE_SIZE 8192' \
			'scripts/config --set-val CONFIG_SYS_NAND_OOBSIZE 640' \
			'scripts/config --set-val CONFIG_SYS_NAND_U_BOOT_OFFS 0x800000'; do
			printf '%s\n' "${CONFIG_CALLS[@]}" | grep -Fxq "$expected"
		done
	else
		[[ ${#CONFIG_CALLS[@]} -eq 3 ]]
	fi
}

assert_profile dev no
assert_profile sd-release no
assert_profile nand-installer yes
assert_profile nand-recovery yes

UBOOT_PATCH="$REPO_ROOT/userpatches/u-boot/v2026.07-sunxi/board_pcduino3b/0001-pcduino3b-enable-onboard-nand.patch"
for expected in \
	'sun7i-a20-pcduino3b.dts' \
	'model = "LinkSprite pcDuino3B";' \
	'phy-mode = "rgmii-id";' \
	'pcduino3b_nand_pins: nand-pins' \
	'func(UBIFS, ubifs, 0, ubi, rootfs)' \
	'label = "spl-primary";' \
	'label = "spl-backup";' \
	'label = "uboot";' \
	'label = "ubi";' \
	'reg = <0x02000000 0xfe000000>;'; do
	grep -Fq "$expected" "$UBOOT_PATCH"
done
if grep -Fq 'diff --git a/arch/arm/dts/sun7i-a20-pcduino3.dts' "$UBOOT_PATCH"; then
	echo 'pcDuino3B U-Boot patch modifies the upstream pcDuino3 DTS' >&2
	exit 1
fi

LAYOUT="$REPO_ROOT/userpatches/overlay/usr/share/pcduino3b/nand-layout.env"
# shellcheck disable=SC1090
source "$LAYOUT"
[[ "$PCDUINO3B_NAND_TOTAL_BYTES" -eq 4294967296 ]]
[[ "$PCDUINO3B_NAND_UBOOT_OFFSET" -eq 8388608 ]]
[[ "$PCDUINO3B_NAND_UBI_OFFSET" -eq 33554432 ]]
[[ "$PCDUINO3B_NAND_UBI_BYTES" -eq 4261412864 ]]
[[ $((PCDUINO3B_NAND_UBI_OFFSET + PCDUINO3B_NAND_UBI_BYTES)) \
	-eq "$PCDUINO3B_NAND_TOTAL_BYTES" ]]
[[ "$PCDUINO3B_NAND_UBI_LEB_BYTES" \
	-eq $((PCDUINO3B_NAND_ERASE_BYTES - PCDUINO3B_NAND_UBI_DATA_OFFSET)) ]]

echo 'pcduino3b NAND U-Boot config fixture: PASS'
