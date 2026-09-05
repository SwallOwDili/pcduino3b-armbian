#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ITS="$REPO_ROOT/userpatches/pcduino3b-nand-boot.its"
WORKFLOW="$REPO_ROOT/.github/workflows/image-build.yml"
PROMOTION="$REPO_ROOT/.github/workflows/release-promotion.yml"

for expected in \
	'description = "pcDuino3B NAND boot FIT";' \
	'data = /incbin/("zImage");' \
	'data = /incbin/("initrd.img");' \
	'/* The gzip stream is passed through for Linux to unpack. */' \
	'data = /incbin/("pcduino3b-nand-runtime.dtb");' \
	'load = <0x42000000>;' \
	'load = <0x43000000>;' \
	'load = <0x43400000>;' \
	'algo = "sha256";' \
	'kernel = "kernel-1";' \
	'ramdisk = "ramdisk-1";' \
	'fdt = "fdt-1";'; do
	grep -Fq "$expected" "$ITS"
done

[[ "$(grep -Fc 'algo = "sha256";' "$ITS")" -eq 3 ]]
[[ "$(grep -Fc 'compression = "none";' "$ITS")" -eq 3 ]]
if grep -Fq 'compression = "gzip";' "$ITS"; then
	echo 'FIT ramdisk compression must be none; Linux handles the embedded gzip stream' >&2
	exit 1
fi
grep -Fq 'mkimage -f pcduino3b-nand-boot.its "$boot_fit"' "$WORKFLOW"
grep -Fq 'gzip -t "$initrd"' "$WORKFLOW"
grep -Fq 'KERNEL_GIT_REF: tag:v6.18.49' "$WORKFLOW"
grep -Fq 'KERNELBRANCH="$KERNEL_GIT_REF"' "$WORKFLOW"
grep -Fq 'config-6.18.49-current-sunxi' "$WORKFLOW"
grep -Fq 'vmlinuz-6.18.49-current-sunxi' "$WORKFLOW"
grep -Fq 'bootfit_bytes <= 67108864' "$WORKFLOW"
grep -Fq "rootfs_partition=/soc/nand-controller@1c03000/nand@0/partitions/partition@8000000" \
	"$WORKFLOW"
grep -Fq 'compatible linux,ubi' "$WORKFLOW"
grep -Fq 'ROOTFS_AUTO_ATTACH=linux,ubi' "$WORKFLOW"
grep -Fq '0x42000000 + kernel_bytes <= 0x43000000' "$WORKFLOW"
grep -Fq '0x43000000 + runtime_dtb_bytes <= 0x43400000' "$WORKFLOW"
grep -Fq '0x43400000 + initrd_bytes <= 0x50000000' "$WORKFLOW"

# Automatic UBI attachment belongs only to the runtime DTB embedded in FIT.
# Enabling it in the SD installer overlay would attach ubi0 before the
# installer's pre-write safety checks run.
if grep -Fq 'linux,ubi' \
	"$REPO_ROOT/userpatches/dts/sun7i-a20-pcduino3b-nand-layout.dtso"; then
	echo 'installer overlay must not auto-attach the rootfs UBI partition' >&2
	exit 1
fi

grep -Fq 'tested_nand_bundle_sha256:' "$PROMOTION"
grep -Fq -- "--pattern '*.tar.zst.sha256'" "$PROMOTION"
grep -Fq 'Hardware-tested NAND bundle SHA-256 does not match candidate' "$PROMOTION"
grep -Fq 'NAND_BUNDLE_SHA256=$bundle_sha' "$PROMOTION"
grep -Fq 'downloaded_image_sha=$(sha256sum "$downloaded_image"' "$PROMOTION"
grep -Fq 'downloaded_bundle_sha=$(sha256sum "$downloaded_bundle"' "$PROMOTION"
grep -Fq 'Downloaded candidate image SHA-256 mismatch' "$PROMOTION"
grep -Fq 'Downloaded NAND bundle SHA-256 mismatch' "$PROMOTION"
grep -Fq 'HARDWARE-ACCEPTANCE-${CANDIDATE_TAG}.txt' "$PROMOTION"
grep -Fq 'CI_REPORT_SHA256=$REPORT_SHA256' "$PROMOTION"
grep -Fq 'sha256sum -c "$attestation_name.sha256"' "$PROMOTION"
grep -Fq 'cmp -s "$attestation" "$verify_dir/$attestation_name"' "$PROMOTION"
grep -Fq -- '--prerelease=false' "$PROMOTION"
[[ "$(grep -Fc '[[ "$status" == PASS ]] || exit 1' "$WORKFLOW")" -eq 2 ]]

# U-Boot reads 64 MiB at 0x50000000; all component destinations stay below it.
fit_load=$((0x50000000))
fit_read_end=$((fit_load + 0x04000000))
kernel_load=$((0x42000000))
fdt_load=$((0x43000000))
ramdisk_load=$((0x43400000))
((kernel_load < fdt_load && fdt_load < ramdisk_load))
((ramdisk_load < fit_load && fit_load < fit_read_end))

echo 'pcduino3b NAND boot FIT fixture: PASS'
