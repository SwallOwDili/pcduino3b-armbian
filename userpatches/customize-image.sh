#!/bin/bash
# arguments: $RELEASE $LINUXFAMILY $BOARD $BUILD_DESKTOP
# Runs inside the target rootfs chroot during the Armbian image build.

set -euo pipefail

RELEASE="$1"
LINUXFAMILY="$2"
BOARD="$3"
BUILD_DESKTOP="$4"
PROFILE_FILE="/tmp/overlay/etc/pcduino3b-image-profile"
IMAGE_PROFILE="${PCDUINO3B_IMAGE_PROFILE:-}"
if [[ -z "$IMAGE_PROFILE" && -r "$PROFILE_FILE" ]]; then
	IMAGE_PROFILE="$(<"$PROFILE_FILE")"
fi
IMAGE_PROFILE="${IMAGE_PROFILE:-sd-release}"

normalize_identity() {
	printf '%s\n' 'pcduino3b' >/etc/hostname

	if grep -qE '^[[:space:]]*127\.0\.1\.1([[:space:]]|$)' /etc/hosts; then
		sed -i -E 's/^[[:space:]]*127\.0\.1\.1([[:space:]].*)?$/127.0.1.1 pcduino3b/' /etc/hosts
	else
		printf '%s\n' '127.0.1.1 pcduino3b' >>/etc/hosts
	fi
}

Main() {
	if [[ "$RELEASE" != "noble" ]]; then
		echo "pcDuino3B image policy requires Ubuntu Noble; got: $RELEASE" >&2
		exit 1
	fi
	if [[ "$LINUXFAMILY" != "sunxi" || "$BOARD" != "pcduino3b" ]]; then
		echo "Unexpected Armbian target: family=$LINUXFAMILY board=$BOARD" >&2
		exit 1
	fi
	case "$IMAGE_PROFILE" in
		dev|sd-release|nand-installer|nand-recovery) ;;
		*)
			echo "Unknown pcDuino3B image profile: $IMAGE_PROFILE" >&2
			exit 1
			;;
	esac
	if [[ "$IMAGE_PROFILE" == nand-* && "$BUILD_DESKTOP" != "no" ]]; then
		echo "NAND profiles require a Minimal/CLI rootfs (BUILD_DESKTOP=no)" >&2
		exit 1
	fi

	export DEBIAN_FRONTEND=noninteractive
	export APT_LISTCHANGES_FRONTEND=none

	cat >/etc/apt/apt.conf.d/80-pcduino3b-network-retries <<'APT'
Acquire::Retries "3";
Acquire::http::Timeout "30";
Acquire::https::Timeout "30";
APT

	# This is deliberately fatal: a published image must have working Ubuntu
	# package metadata during construction, rather than deferring discovery of a
	# broken source configuration to first boot.
	apt-get update

	# Validate both DNS/TLS and the canonical Ubuntu ARM archive endpoint used by
	# Noble.  A failure aborts the image build.
	getent ahosts ports.ubuntu.com >/dev/null
	curl --fail --silent --show-error --location --head \
		--connect-timeout 15 --max-time 45 \
		https://ports.ubuntu.com/ubuntu-ports/dists/noble/InRelease >/dev/null

	install -D -m 0755 /tmp/overlay/usr/local/sbin/pcduino3b-selftest \
		/usr/local/sbin/pcduino3b-selftest
	if [[ "$IMAGE_PROFILE" == nand-* ]]; then
		install -D -m 0755 /tmp/overlay/usr/local/sbin/pcduino3b-nand-probe \
			/usr/local/sbin/pcduino3b-nand-probe
	fi
	normalize_identity

	cat >/etc/pcduino3b-build-info <<INFO
BOARD=pcDuino3B
ARMBIAN_BOARD=pcduino3b
ARMBIAN_FAMILY=$LINUXFAMILY
UBUNTU_CODENAME=$RELEASE
IMAGE_PROFILE=$IMAGE_PROFILE
KERNEL_POLICY=Armbian current (sunxi Linux 6.18.y)
ETHERNET_POLICY=A20 GMAC RGMII-ID + built-in STMMAC/DWMAC_SUNXI/REALTEK_PHY
BUILD_SOURCE_TEST=apt-get update + HTTPS ports.ubuntu.com Noble InRelease
INFO

	# The source test above is mandatory, but its downloaded metadata is build
	# residue.  First-boot acceptance deliberately runs apt-get update again.
	apt-get clean
	rm -rf /var/lib/apt/lists/*
}

Main "$@"
