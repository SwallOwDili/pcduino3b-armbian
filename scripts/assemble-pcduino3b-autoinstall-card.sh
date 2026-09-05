#!/usr/bin/env bash
# Build a dedicated, self-contained SD card that automatically installs NAND.

set -euo pipefail

usage() {
	cat <<'USAGE'
Usage: assemble-pcduino3b-autoinstall-card.sh INPUT.img PAYLOAD_DIR OUTPUT.img
USAGE
}

[[ $# -eq 3 ]] || {
	usage >&2
	exit 2
}
[[ $EUID -eq 0 ]] || {
	echo 'ERROR: run as root (loop mounts and FAT creation are required)' >&2
	exit 1
}

readonly input_image=$(readlink -f "$1")
readonly payload_dir=$(readlink -f "$2")
readonly output_image=$(readlink -m "$3")
readonly repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly partition_tool=$repo_root/scripts/add-pcduino3b-installer-partition.py
readonly runner_source=$repo_root/installer-card/pcduino3b-nand-autoinstall
readonly service_source=$repo_root/installer-card/pcduino3b-nand-autoinstall.service
readonly readme_source=$repo_root/installer-card/README.txt

for command_name in \
	awk cat cmp cp cpio find grep gzip install ln losetup mkfs.vfat mkimage \
	mknod mount mountpoint python3 readlink rm rmdir sed sha256sum stat sync touch \
	udevadm umount; do
	command -v "$command_name" >/dev/null 2>&1 || {
		echo "ERROR: required command is missing: $command_name" >&2
		exit 1
	}
done

loop_device=
root_mount=
fat_mount=
created_partition_nodes=()

cleanup() {
	set +e
	[[ -n "$fat_mount" ]] && mountpoint -q "$fat_mount" && umount "$fat_mount"
	[[ -n "$root_mount" ]] && mountpoint -q "$root_mount" && umount "$root_mount"
	[[ -n "$loop_device" ]] && losetup -d "$loop_device"
	((${#created_partition_nodes[@]} == 0)) || rm -f -- "${created_partition_nodes[@]}"
	[[ -n "$fat_mount" ]] && rmdir "$fat_mount" 2>/dev/null
	[[ -n "$root_mount" ]] && rmdir "$root_mount" 2>/dev/null
}
trap cleanup EXIT INT TERM

for required in "$input_image" "$payload_dir/SHA256SUMS" "$partition_tool" \
	"$runner_source" "$service_source" "$readme_source"; do
	[[ -e "$required" ]] || {
		echo "ERROR: required input is missing: $required" >&2
		exit 1
	}
done
[[ "$output_image" != "$input_image" ]] || {
	echo 'ERROR: output must not overwrite the accepted base image' >&2
	exit 1
}

for required_name in \
	pcduino3b-nand-rootfs.ubi \
	pcduino3b-nand-boot.itb \
	pcduino3b-nand-spl-with-ecc.bin \
	pcduino3b-nand-u-boot.bin \
	pcduino3b-nand-layout.env \
	pcduino3b-nand-layout.dtbo \
	pcduino3b-nand-install \
	pcduino3b-nand-manifest.txt; do
	[[ -s "$payload_dir/$required_name" ]] || {
		echo "ERROR: payload file is missing: $required_name" >&2
		exit 1
	}
done
(
	cd "$payload_dir"
	sha256sum -c SHA256SUMS
)

install -d -m 0755 "$(dirname "$output_image")"
cp --reflink=auto --sparse=always "$input_image" "$output_image"
python3 "$partition_tool" "$output_image"

loop_device=$(losetup --find --show --partscan "$output_image")
udevadm settle
root_partition=${loop_device}p1
fat_partition=${loop_device}p2

# A normal GitHub runner creates loop partition nodes through udev.  Minimal
# build containers expose the partition numbers in sysfs but may not run a
# device manager, so create only those exact nodes when necessary.
for partition_node in "$root_partition" "$fat_partition"; do
	[[ -b "$partition_node" ]] && continue
	partition_name=${partition_node##*/}
	dev_number_file=/sys/class/block/$partition_name/dev
	[[ -r "$dev_number_file" ]] || continue
	IFS=: read -r major_number minor_number <"$dev_number_file"
	[[ "$major_number" =~ ^[0-9]+$ && "$minor_number" =~ ^[0-9]+$ ]] || continue
	mknod "$partition_node" b "$major_number" "$minor_number"
	created_partition_nodes+=("$partition_node")
done
[[ -b "$root_partition" && -b "$fat_partition" ]] || {
	lsblk "$loop_device" >&2
	echo 'ERROR: installer-card partitions did not appear' >&2
	exit 1
}

mkfs.vfat -F 32 -n PCD3BINS "$fat_partition"
root_mount=$(mktemp -d)
fat_mount=$(mktemp -d)
mount "$root_partition" "$root_mount"
mount -t vfat -o rw,nosuid,nodev,noexec "$fat_partition" "$fat_mount"

grep -qx 'VERSION_CODENAME=noble' "$root_mount/etc/os-release"
grep -qx 'ARMBIAN_BOARD=pcduino3b' "$root_mount/etc/pcduino3b-build-info"
grep -qx 'IMAGE_PROFILE=nand-installer' "$root_mount/etc/pcduino3b-build-info"

install -D -m 0755 "$runner_source" \
	"$root_mount/usr/local/sbin/pcduino3b-nand-autoinstall"
install -D -m 0644 "$service_source" \
	"$root_mount/etc/systemd/system/pcduino3b-nand-autoinstall.service"
install -d -m 0755 "$root_mount/etc/systemd/system/multi-user.target.wants"
ln -sfn ../pcduino3b-nand-autoinstall.service \
	"$root_mount/etc/systemd/system/multi-user.target.wants/pcduino3b-nand-autoinstall.service"

# The NAND module is required in the FIT initramfs already copied into the
# payload, but loading it during SD initramfs was observed to block startup.
# A final overlay archive clears the forced module list and adds a blacklist;
# the one-shot service loads the module explicitly after userspace is ready.
sed -i '/^[[:space:]]*sunxi_nand\([[:space:]].*\)\?$/d' \
	"$root_mount/etc/initramfs-tools/modules"
install -d -m 0755 "$root_mount/etc/modprobe.d"
printf '%s\n' 'blacklist sunxi_nand' \
	>"$root_mount/etc/modprobe.d/pcduino3b-nand-installer.conf"

boot_env=$root_mount/boot/armbianEnv.txt
if grep -q '^extraargs=' "$boot_env"; then
	if ! grep -Eq '^extraargs=.*modprobe\.blacklist=sunxi_nand([[:space:]]|$)' "$boot_env"; then
		sed -i '/^extraargs=/ s/$/ modprobe.blacklist=sunxi_nand/' "$boot_env"
	fi
else
	printf '%s\n' 'extraargs=modprobe.blacklist=sunxi_nand' >>"$boot_env"
fi

mapfile -t initrds < <(find "$root_mount/boot" -maxdepth 1 -type f \
	-name 'initrd.img-*-current-sunxi' -print | sort)
[[ ${#initrds[@]} -eq 1 ]] || {
	echo "ERROR: expected one current-sunxi initrd, found ${#initrds[@]}" >&2
	exit 1
}
initrd=${initrds[0]}
kernel_release=${initrd##*/initrd.img-}
uinitrd=$root_mount/boot/uInitrd-$kernel_release
[[ -s "$uinitrd" ]] || {
	echo "ERROR: matching U-Boot initrd is missing: $uinitrd" >&2
	exit 1
}

overlay_dir=$(mktemp -d)
install -d -m 0755 "$overlay_dir/conf" "$overlay_dir/etc/modprobe.d"
: >"$overlay_dir/conf/modules"
printf '%s\n' 'blacklist sunxi_nand' \
	>"$overlay_dir/etc/modprobe.d/pcduino3b-nand-installer.conf"
find "$overlay_dir" -exec touch -h -d '@0' {} +
overlay_gzip=$overlay_dir/sd-safe-overlay.cpio.gz
(
	cd "$overlay_dir"
	find conf etc -print0 \
		| LC_ALL=C sort -z \
		| cpio --null --create --format=newc --owner=0:0 --reproducible 2>/dev/null \
		| gzip -n -9 >"$overlay_gzip"
)
cat "$overlay_gzip" >>"$initrd"
gzip -t "$initrd"
mkimage -A arm -O linux -T ramdisk -C gzip \
	-n "pcDuino3B SD-safe initramfs $kernel_release" \
	-d "$initrd" "$uinitrd.new" >/dev/null
mv -f "$uinitrd.new" "$uinitrd"
rm -rf "$overlay_dir"

install -d -m 0755 "$fat_mount/payload" "$fat_mount/logs" "$fat_mount/state"
cp -f "$payload_dir"/* "$fat_mount/payload/"
cp -f "$readme_source" "$fat_mount/README.txt"
{
	echo 'FORMAT_VERSION=1'
	echo 'BOARD=pcduino3b'
	echo 'PURPOSE=nand-autoinstall-card'
	echo 'PAYLOAD_VOLUME=PCD3BINS'
	echo "SOURCE_COMMIT=${GITHUB_SHA:-unknown}"
	echo "BASE_IMAGE_SHA256=$(sha256sum "$input_image" | awk '{print $1}')"
	echo "PAYLOAD_SHA256SUMS_SHA256=$(sha256sum "$payload_dir/SHA256SUMS" | awk '{print $1}')"
} >"$fat_mount/CARD-MANIFEST.txt"
(
	cd "$fat_mount/payload"
	sha256sum -c SHA256SUMS
)

sync
umount "$fat_mount"
umount "$root_mount"

# Re-open both filesystems read-only and prove the final on-disk state.
mount -o ro "$root_partition" "$root_mount"
mount -t vfat -o ro,nosuid,nodev,noexec "$fat_partition" "$fat_mount"
grep -Fxq 'blacklist sunxi_nand' \
	"$root_mount/etc/modprobe.d/pcduino3b-nand-installer.conf"
grep -Eq '^extraargs=.*modprobe\.blacklist=sunxi_nand([[:space:]]|$)' "$boot_env"
[[ -L "$root_mount/etc/systemd/system/multi-user.target.wants/pcduino3b-nand-autoinstall.service" ]]
cmp "$runner_source" "$root_mount/usr/local/sbin/pcduino3b-nand-autoinstall"
cmp "$service_source" "$root_mount/etc/systemd/system/pcduino3b-nand-autoinstall.service"
(
	cd "$fat_mount/payload"
	sha256sum -c SHA256SUMS
)
grep -qx 'PURPOSE=nand-autoinstall-card' "$fat_mount/CARD-MANIFEST.txt"

echo "AUTOINSTALL_IMAGE=$output_image"
echo "AUTOINSTALL_IMAGE_BYTES=$(stat -c %s "$output_image")"
echo "AUTOINSTALL_IMAGE_SHA256=$(sha256sum "$output_image" | awk '{print $1}')"
echo 'AUTOINSTALL_CARD_ASSEMBLY=PASS'
