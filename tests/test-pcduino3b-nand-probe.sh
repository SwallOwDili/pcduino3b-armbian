#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE="$REPO_ROOT/userpatches/overlay/usr/local/sbin/pcduino3b-nand-probe"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

# The shipped probe must remain observational: no module loading, attachment,
# block copying, erase operation or NAND programming is permitted.
FORBIDDEN='(^|[^[:alnum:]_])(modprobe|flash_erase|nandwrite|ubiformat|ubiattach|dd)([^[:alnum:]_]|$)'
if grep -Ev '^[[:space:]]*#' "$PROBE" | grep -Eq "$FORBIDDEN"; then
	echo 'NAND probe contains a mutating command' >&2
	exit 1
fi

mkdir -p "$TEST_ROOT/proc" "$TEST_ROOT/dev" "$TEST_ROOT/sys" "$TEST_ROOT/boot" "$TEST_ROOT/etc"
printf 'dev:    size   erasesize  name\n' >"$TEST_ROOT/proc/mtd"
printf 'IMAGE_PROFILE=nand-recovery\n' >"$TEST_ROOT/etc/pcduino3b-build-info"
printf '%s\n' \
	'fdtfile=allwinner/sun7i-a20-pcduino3b.dtb' \
	'user_overlays=pcduino3b-nand-recovery' \
	>"$TEST_ROOT/boot/armbianEnv.txt"

set +e
OUTPUT="$(
	PCDUINO3B_PROC_ROOT="$TEST_ROOT/proc" \
	PCDUINO3B_PROC_DT_ROOT="$TEST_ROOT/proc/device-tree" \
	PCDUINO3B_DEV_ROOT="$TEST_ROOT/dev" \
	PCDUINO3B_SYS_ROOT="$TEST_ROOT/sys" \
	PCDUINO3B_BOOT_ROOT="$TEST_ROOT/boot" \
	PCDUINO3B_ETC_ROOT="$TEST_ROOT/etc" \
		bash "$PROBE" 2>&1
)"
STATUS=$?
set -e

[[ $STATUS -eq 3 ]]
grep -Fq 'MODE=READ_ONLY' <<<"$OUTPUT"
grep -Fq 'INSTALLER=NOT_AUTHORIZED' <<<"$OUTPUT"
grep -Fq 'IMAGE_PROFILE=nand-recovery' <<<"$OUTPUT"
grep -Fq 'fdtfile=allwinner/sun7i-a20-pcduino3b.dtb' <<<"$OUTPUT"
grep -Fq 'user_overlays=pcduino3b-nand-recovery' <<<"$OUTPUT"
grep -Fq 'sunxi_nand module is not loaded' <<<"$OUTPUT"
grep -Fq 'PROBE_STATUS=NOT_READY' <<<"$OUTPUT"

mkdir -p "$TEST_ROOT/sys/class/mtd/mtd0"
touch "$TEST_ROOT/dev/mtd0"
printf 'mtd0: 100000000 00200000 "1c03000.nand-controller"\n' >>"$TEST_ROOT/proc/mtd"
for field_value in \
	'name=1c03000.nand-controller' \
	'type=mlc-nand' \
	'size=4294967296' \
	'erasesize=2097152' \
	'writesize=8192' \
	'subpagesize=8192' \
	'oobsize=640' \
	'ecc_strength=40' \
	'ecc_step_size=1024'; do
	field=${field_value%%=*}
	value=${field_value#*=}
	printf '%s\n' "$value" >"$TEST_ROOT/sys/class/mtd/mtd0/$field"
done

OUTPUT="$(
	PCDUINO3B_PROC_ROOT="$TEST_ROOT/proc" \
	PCDUINO3B_PROC_DT_ROOT="$TEST_ROOT/proc/device-tree" \
	PCDUINO3B_DEV_ROOT="$TEST_ROOT/dev" \
	PCDUINO3B_SYS_ROOT="$TEST_ROOT/sys" \
	PCDUINO3B_BOOT_ROOT="$TEST_ROOT/boot" \
	PCDUINO3B_ETC_ROOT="$TEST_ROOT/etc" \
		bash "$PROBE" 2>&1
)"

grep -Fq 'writesize=8192' <<<"$OUTPUT"
grep -Fq 'oobsize=640' <<<"$OUTPUT"
grep -Fq 'ecc_strength=40' <<<"$OUTPUT"
grep -Fq 'ecc_step_size=1024' <<<"$OUTPUT"
grep -Fq 'PROBE_STATUS=READ_ONLY_DATA_AVAILABLE' <<<"$OUTPUT"
grep -Fq 'INSTALLER=NOT_AUTHORIZED' <<<"$OUTPUT"

echo 'pcduino3b-nand-probe safety fixture: PASS'
