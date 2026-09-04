#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../userpatches/extensions/pcduino3b-gigabit.sh
source "$REPO_ROOT/userpatches/extensions/pcduino3b-gigabit.sh"

add_packages_to_image() {
	ADDED_PACKAGES=("$@")
}

assert_suffixes() {
	local profile=$1
	local expected=$2
	EXTRA_IMAGE_SUFFIXES=()
	PCDUINO3B_IMAGE_PROFILE=$profile
	extension_prepare_config__pcduino3b_profile_suffix
	[[ "${EXTRA_IMAGE_SUFFIXES[*]-}" == "$expected" ]] || {
		echo "unexpected suffix for $profile: ${EXTRA_IMAGE_SUFFIXES[*]-<empty>}" >&2
		exit 1
	}
}

assert_suffixes dev ""
assert_suffixes sd-release ""
assert_suffixes nand-installer "-nand-installer"
assert_suffixes nand-recovery "-nand-recovery"

assert_dtb() {
	local profile=$1
	local expected=$2
	BOOT_FDT_FILE="allwinner/sun7i-a20-pcduino3b.dtb"
	PCDUINO3B_IMAGE_PROFILE=$profile
	extension_prepare_config__pcduino3b_profile_dtb
	[[ "$BOOT_FDT_FILE" == "$expected" ]] || {
		echo "unexpected DTB for $profile: $BOOT_FDT_FILE" >&2
		exit 1
	}
}

assert_dtb dev "allwinner/sun7i-a20-pcduino3b.dtb"
assert_dtb sd-release "allwinner/sun7i-a20-pcduino3b.dtb"
assert_dtb nand-installer "allwinner/sun7i-a20-pcduino3b.dtb"
assert_dtb nand-recovery "allwinner/sun7i-a20-pcduino3b.dtb"

assert_uboot_targets() {
	local profile=$1
	local expected=$2
	UBOOT_TARGET_MAP=';;u-boot-sunxi-with-spl.bin'
	PCDUINO3B_IMAGE_PROFILE=$profile
	extension_prepare_config__pcduino3b_nand_uboot_artifacts
	[[ "$UBOOT_TARGET_MAP" == "$expected" ]] || {
		echo "unexpected U-Boot targets for $profile: $UBOOT_TARGET_MAP" >&2
		exit 1
	}
}

assert_uboot_targets dev ';;u-boot-sunxi-with-spl.bin'
assert_uboot_targets sd-release ';;u-boot-sunxi-with-spl.bin'
assert_uboot_targets nand-installer ';;u-boot-sunxi-with-spl.bin spl/sunxi-spl-with-ecc.bin:pcduino3b-nand-spl-with-ecc.bin u-boot-dtb.bin:pcduino3b-nand-u-boot.bin'
assert_uboot_targets nand-recovery ';;u-boot-sunxi-with-spl.bin spl/sunxi-spl-with-ecc.bin:pcduino3b-nand-spl-with-ecc.bin u-boot-dtb.bin:pcduino3b-nand-u-boot.bin'

ADDED_PACKAGES=()
PCDUINO3B_EXTRA_PACKAGES="curl ethtool openssh-server"
extension_prepare_config__pcduino3b_packages
[[ "${ADDED_PACKAGES[*]}" == "curl ethtool openssh-server" ]] || {
	echo "unexpected profile packages: ${ADDED_PACKAGES[*]-<empty>}" >&2
	exit 1
}

echo "pcduino3b profile suffix fixture: PASS"
