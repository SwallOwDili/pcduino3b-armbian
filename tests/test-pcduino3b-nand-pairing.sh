#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# Shell model of the kernel dist6 get_wunit callback.  The fixed examples are
# transcribed from H27UBG8T2CTR-BC data-sheet pages 56-57.
dist6_wunit() {
	local pair=$1 group=$2 page last2pages=0
	page=$(((pair & ~1) + (3 * group)))
	((page * 2 * 8192 > 2097152)) && last2pages=1
	page=$((page - (page != 0) - last2pages))
	printf '%d\n' "$(((2 * page) + (pair & 1)))"
}

dist6_info() {
	local physical_page=$1 page lsbit last2pages=0 group pair
	lsbit=$((physical_page & 1))
	page=$((physical_page >> 1))
	(( (page + 1) * 2 * 8192 == 2097152 )) && last2pages=1
	page=$((page + (page != 0) + last2pages))
	group=$((page & 1))
	((group == 0)) || page=$((page - 3))
	pair=$((page | lsbit))
	printf '%d %d\n' "$pair" "$group"
}

while read -r pair first_group second_group; do
	[[ "$(dist6_wunit "$pair" 0)" -eq "$first_group" ]]
	[[ "$(dist6_wunit "$pair" 1)" -eq "$second_group" ]]
done <<'DATASHEET_PAIRS'
0 0x00 0x04
1 0x01 0x05
2 0x02 0x08
3 0x03 0x09
4 0x06 0x0c
5 0x07 0x0d
62 0x7a 0x80
63 0x7b 0x81
64 0x7e 0x84
65 0x7f 0x85
126 0xfa 0xfe
127 0xfb 0xff
DATASHEET_PAIRS

for physical_page in $(seq 0 255); do
	read -r pair group < <(dist6_info "$physical_page")
	[[ "$pair" -ge 0 && "$pair" -lt 128 ]]
	[[ "$group" -eq 0 || "$group" -eq 1 ]]
	[[ "$(dist6_wunit "$pair" "$group")" -eq "$physical_page" ]]
done

for series in 6.12 6.18 7.1; do
	patch="$REPO_ROOT/userpatches/kernel/archive/sunxi-$series/0002-mtd-rawnand-add-h27ubg8t2c.patch"
	grep -Fq 'const struct mtd_pairing_scheme dist6_pairing_scheme' "$patch"
	grep -Fq 'mtd_set_pairing_scheme(mtd, &dist6_pairing_scheme);' "$patch"
	grep -Fq 'H27UBG8T2CTR-BC' "$patch"
done

echo 'pcduino3b H27UBG8T2C dist6 pairing fixture: PASS'
