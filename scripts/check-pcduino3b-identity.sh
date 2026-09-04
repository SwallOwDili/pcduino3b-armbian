#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

FAILURES=0

fail() {
	printf 'identity lint: FAIL: %s\n' "$*" >&2
	FAILURES=$((FAILURES + 1))
}

require_match() {
	local pattern="$1"
	local file="$2"
	local description="$3"
	grep -Eq "$pattern" "$file" || fail "$description ($file)"
}

forbid_match() {
	local pattern="$1"
	local description="$2"
	shift 2
	local output

	output="$(rg -n -e "$pattern" "$@" 2>/dev/null || true)"
	if [[ -n "$output" ]]; then
		printf '%s\n' "$output" >&2
		fail "$description"
	fi
}

BOARD_FILE="userpatches/config/boards/pcduino3b.csc"
CUSTOMIZE="userpatches/customize-image.sh"
PATCH_FILE="userpatches/kernel/archive/sunxi-6.18/0001-arm-dts-sun7i-a20-pcduino3b-gigabit.patch"
SELFTEST="userpatches/overlay/usr/local/sbin/pcduino3b-selftest"
NAND_PROBE="userpatches/overlay/usr/local/sbin/pcduino3b-nand-probe"

require_match '^BOARD_NAME="pcDuino3B"$' "$BOARD_FILE" 'BOARD_NAME must be pcDuino3B'
require_match '^BOARDFAMILY="sun7i"$' "$BOARD_FILE" 'BOARDFAMILY must remain sun7i'
require_match '^BOOTCONFIG="Linksprite_pcDuino3_defconfig"$' "$BOARD_FILE" 'expected U-Boot compatibility defconfig is missing'
require_match '^BOOT_FDT_FILE="allwinner/sun7i-a20-pcduino3b\.dtb"$' "$BOARD_FILE" 'board must select the dedicated pcDuino3B DTB'
require_match '^KERNEL_TARGET="current,edge,legacy"$' "$BOARD_FILE" 'board must expose current, edge and legacy kernel targets'

require_match '\$BOARD" != "pcduino3b"' "$CUSTOMIZE" 'customize-image must reject targets other than pcduino3b'
require_match '^ARMBIAN_BOARD=pcduino3b$' "$CUSTOMIZE" 'build-info must use the pcduino3b slug'
require_match "printf '%s\\\\n' 'pcduino3b' >/etc/hostname" "$CUSTOMIZE" 'customize-image must create /etc/hostname'
require_match '127[.]0[.]1[.]1 pcduino3b' "$CUSTOMIZE" 'customize-image must synchronize /etc/hosts'
require_match 'PCDUINO3B_IMAGE_PROFILE' "$CUSTOMIZE" 'profile input must use the normalized uppercase variable'
require_match '\[\[ "\$IMAGE_PROFILE" == nand-\* \]\]' "$CUSTOMIZE" 'NAND payload must be profile-gated'

require_match 'sun7i-a20-pcduino3b\.dts' "$PATCH_FILE" 'dedicated DTS is missing from the kernel patch'
require_match 'sun7i-a20-pcduino3b\.dtb' "$PATCH_FILE" 'dedicated DTB is missing from the kernel Makefile patch'
require_match 'model = "LinkSprite pcDuino3B";' "$PATCH_FILE" 'dedicated DT model is incorrect'
require_match '#include "sun7i-a20-pcduino3\.dts"' "$PATCH_FILE" 'upstream pcDuino3 include must remain an explicit compatibility layer'
require_match 'phy-mode = "rgmii-id";' "$PATCH_FILE" 'pcDuino3B GMAC mode is missing'
if grep -Eq '^diff --git a/arch/arm/boot/dts/allwinner/sun7i-a20-pcduino3\.dts ' "$PATCH_FILE"; then
	fail 'kernel patch must not modify the original pcDuino3 DTS'
fi
for series in 6.12 6.18 7.1; do
	series_patch="userpatches/kernel/archive/sunxi-${series}/$(basename "$PATCH_FILE")"
	[[ -r "$series_patch" ]] || {
		fail "dedicated pcDuino3B DT patch is missing for sunxi-$series"
		continue
	}
	cmp -s "$PATCH_FILE" "$series_patch" ||
		fail "pcDuino3B DT patch diverged for sunxi-$series"
done

require_match 'find -L "\$PROC_DT_ROOT"' "$SELFTEST" 'selftest must follow the /proc/device-tree symlink'
require_match 'BOARD is pcduino3b' "$SELFTEST" 'selftest must validate Armbian BOARD identity'
require_match 'ARMBIAN_BOARD is pcduino3b' "$SELFTEST" 'selftest must validate build-info identity'
require_match 'RTL8211E PHY is bound' "$SELFTEST" 'selftest must accept the verified RTL8211E identity'
require_match 'detect_ethernet_interface' "$SELFTEST" 'selftest must discover the routed Ethernet interface'

forbid_match 'armbian_board:.*pcduino3([^b[:alnum:]_]|$)' \
	'workflow still builds the legacy board slug' .github/workflows
forbid_match 'ARMBIAN_BOARD=pcduino3$' \
	'legacy Armbian board metadata remains' userpatches README.md docs/INSTALL.md
forbid_match '_Pcduino3_' \
	'legacy product name remains in an artifact pattern' .github/workflows README.md docs/INSTALL.md
forbid_match 'pc[Dd]uino3[[:space:]_-]*[Nn]ano' \
	'unsupported Nano identity leaked into a current user-visible file' README.md docs/INSTALL.md userpatches/customize-image.sh "$BOARD_FILE"
forbid_match 'sun7i-a20-pcduino3\.dtb' \
	'current boot or installation documentation selects the legacy DTB' README.md docs/INSTALL.md "$BOARD_FILE"

for manifest in common dev sd-release nand-installer nand-recovery; do
	file="packages/$manifest.txt"
	[[ -r "$file" ]] || {
		fail "package manifest is missing: $file"
		continue
	}
	invalid="$(awk '!/^[[:space:]]*(#|$)/ && $0 !~ /^[a-z0-9][a-z0-9+.-]*$/ { print NR ":" $0 }' "$file")"
	[[ -z "$invalid" ]] || {
		printf '%s\n' "$invalid" >&2
		fail "invalid package entry in $file"
	}
done

MUTATING_NAND_COMMAND='(^|[^[:alnum:]_])(modprobe|flash_erase|nandwrite|ubiformat|ubiattach|dd)([^[:alnum:]_]|$)'
if grep -Ev '^[[:space:]]*#' "$NAND_PROBE" | grep -Eq "$MUTATING_NAND_COMMAND"; then
	fail 'NAND probe contains a mutating operation'
fi
require_match 'MODE=READ_ONLY' "$NAND_PROBE" 'NAND probe must declare read-only mode'
require_match 'PROBE_STATUS=NOT_READY' "$NAND_PROBE" 'NAND probe must expose the NOT_READY safety result'
require_match 'INSTALLER=NOT_AUTHORIZED' "$NAND_PROBE" 'NAND probe must keep the installer safety gate closed'

if ((FAILURES > 0)); then
	printf 'identity lint: %d failure(s)\n' "$FAILURES" >&2
	exit 1
fi

echo 'identity lint: PASS'
