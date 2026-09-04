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

ADDED_PACKAGES=()
PCDUINO3B_EXTRA_PACKAGES="curl ethtool openssh-server"
extension_prepare_config__pcduino3b_packages
[[ "${ADDED_PACKAGES[*]}" == "curl ethtool openssh-server" ]] || {
	echo "unexpected profile packages: ${ADDED_PACKAGES[*]-<empty>}" >&2
	exit 1
}

echo "pcduino3b profile suffix fixture: PASS"
