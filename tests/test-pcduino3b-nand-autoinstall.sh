#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RUNNER="$REPO_ROOT/installer-card/pcduino3b-nand-autoinstall"
SERVICE="$REPO_ROOT/installer-card/pcduino3b-nand-autoinstall.service"
ASSEMBLER="$REPO_ROOT/scripts/assemble-pcduino3b-autoinstall-card.sh"
PARTITION_TOOL="$REPO_ROOT/scripts/add-pcduino3b-installer-partition.py"

for file in "$RUNNER" "$SERVICE" "$ASSEMBLER" "$PARTITION_TOOL"; do
	[[ -s "$file" ]]
done
bash -n "$RUNNER"
bash -n "$ASSEMBLER"

grep -Fxq 'readonly CARD_LABEL=PCD3BINS' "$RUNNER"
grep -Fq 'payload partition is not on the boot microSD' "$RUNNER"
grep -Fq 'refusing an automatic retry' "$RUNNER"
grep -Fq 'journal-current-boot.log' "$RUNNER"
grep -Fq 'dmesg --follow-new' "$RUNNER"
grep -Fq 'modprobe sunxi_nand' "$RUNNER"
grep -Fq -- '--host-backup-confirmed' "$RUNNER"
grep -Fq 'ERASE-PCDUINO3B-NAND-$PCDUINO3B_NAND_ID' "$RUNNER"
grep -Fq 'AUTOINSTALL_STATUS=PASS' "$RUNNER"
grep -Fq 'SUCCESS.txt' "$RUNNER"
grep -Fq 'systemctl poweroff' "$RUNNER"

modprobe_line=$(grep -n '^modprobe sunxi_nand$' "$RUNNER" | cut -d: -f1)
install_line=$(grep -n '^/bin/bash "$PAYLOAD_DIR/pcduino3b-nand-install"' "$RUNNER" | cut -d: -f1)
pass_line=$(grep -n "^echo 'AUTOINSTALL_STATUS=PASS'$" "$RUNNER" | cut -d: -f1)
success_line=$(grep -n 'SUCCESS.tmp' "$RUNNER" | tail -n1 | cut -d: -f1)
poweroff_line=$(grep -n '^systemctl poweroff$' "$RUNNER" | tail -n1 | cut -d: -f1)
((modprobe_line < install_line && install_line < pass_line && pass_line < success_line && success_line < poweroff_line))

if grep -Ev '^[[:space:]]*#' "$RUNNER" \
	| grep -Eq '(^|[^[:alnum:]_])(flash_erase|nandwrite|ubiformat|ubiattach|dd)([^[:alnum:]_]|$)'; then
	echo 'automatic wrapper must delegate all NAND writes to the guarded installer' >&2
	exit 1
fi

grep -Fxq 'ExecStart=/usr/local/sbin/pcduino3b-nand-autoinstall' "$SERVICE"
grep -Fxq 'TimeoutStartSec=infinity' "$SERVICE"
grep -Fq 'cp --reflink=auto --sparse=always "$input_image" "$output_image"' "$ASSEMBLER"
grep -Fq 'mkfs.vfat -F 32 -n PCD3BINS' "$ASSEMBLER"
grep -Fq 'modprobe.blacklist=sunxi_nand' "$ASSEMBLER"
grep -Fq 'pcduino3b-nand-autoinstall.service' "$ASSEMBLER"
grep -Fq 'sha256sum -c SHA256SUMS' "$ASSEMBLER"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
image="$tmp_dir/fixture.img"
python3 - "$image" <<'PY'
import struct
import sys

path = sys.argv[1]
size = 16 * 1024 * 1024
mbr = bytearray(512)
mbr[446:462] = struct.pack(
    "<B3sB3sII", 0, b"\x00\x02\x00", 0x83, b"\xfe\xff\xff", 8192, 8192
)
mbr[510:512] = b"\x55\xaa"
with open(path, "wb") as handle:
    handle.write(mbr)
    handle.truncate(size)
PY

python3 -c 'import py_compile,sys; py_compile.compile(sys.argv[1], cfile=sys.argv[2], doraise=True)' \
	"$PARTITION_TOOL" "$tmp_dir/partition.pyc"
python3 "$PARTITION_TOOL" "$image" --payload-bytes 1048576 \
	>"$tmp_dir/partition.out"
python3 - "$image" <<'PY'
import struct
import sys

path = sys.argv[1]
with open(path, "rb") as handle:
    mbr = handle.read(512)

def entry(index):
    offset = 446 + index * 16
    return mbr[offset + 4], *struct.unpack_from("<II", mbr, offset + 8)

assert mbr[510:512] == b"\x55\xaa"
assert entry(0) == (0x83, 8192, 8192)
assert entry(1) == (0x0C, 32768, 2048)
assert entry(2) == (0, 0, 0)
assert entry(3) == (0, 0, 0)
assert __import__("os").path.getsize(path) == (32768 + 2048) * 512
PY

if python3 "$PARTITION_TOOL" "$image" --payload-bytes 1048576 \
	>"$tmp_dir/retry.out" 2>"$tmp_dir/retry.err"; then
	echo 'partition helper accepted an already occupied second entry' >&2
	exit 1
fi
grep -Fq 'partition entry 2 is already occupied' "$tmp_dir/retry.err"

echo 'pcduino3b automatic NAND installer fixture: PASS'
