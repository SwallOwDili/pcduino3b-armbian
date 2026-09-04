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
	'boot-region bad-block count' \
	'sha256sum -c SHA256SUMS' \
	'host backup SHA-256' \
	'--host-backup-confirmed is required' \
	'ERASE-PCDUINO3B-NAND-$PCDUINO3B_NAND_ID' \
	'INSTALL_STATUS=PASS'; do
	grep -Fq -- "$guard" "$INSTALLER"
done

plan_exit_line=$(grep -n "NAND_WRITE=NOT_REQUESTED" "$INSTALLER" | cut -d: -f1)
first_write_line=$(grep -nE '^[[:space:]]*(ubiformat|flash_erase|nandwrite)[[:space:]]' \
	"$INSTALLER" | head -n1 | cut -d: -f1)
[[ -n "$plan_exit_line" && -n "$first_write_line" ]]
((plan_exit_line < first_write_line))

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
	-eq "$PCDUINO3B_NAND_UBI_OFFSET" ]]
[[ $((PCDUINO3B_NAND_UBI_OFFSET + PCDUINO3B_NAND_UBI_BYTES)) \
	-eq "$PCDUINO3B_NAND_TOTAL_BYTES" ]]

for label in spl-primary spl-backup uboot ubi; do
	grep -Fq "label = \"$label\";" "$OVERLAY"
done
grep -Fq 'reg = <0x02000000 0xfe000000>;' "$OVERLAY"

echo 'pcduino3b NAND installer safety fixture: PASS'
