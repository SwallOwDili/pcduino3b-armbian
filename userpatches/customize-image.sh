#!/bin/bash
# arguments: $RELEASE $LINUXFAMILY $BOARD $BUILD_DESKTOP
# Runs inside the target rootfs chroot during the Armbian image build.

set -euo pipefail

RELEASE="$1"
LINUXFAMILY="$2"
BOARD="$3"
BUILD_DESKTOP="$4"

Main() {
	if [[ "$RELEASE" != "noble" ]]; then
		echo "pcDuino3B image policy requires Ubuntu Noble; got: $RELEASE" >&2
		exit 1
	fi
	if [[ "$LINUXFAMILY" != "sunxi" || "$BOARD" != "pcduino3" ]]; then
		echo "Unexpected Armbian target: family=$LINUXFAMILY board=$BOARD" >&2
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

	apt-get install -y --no-install-recommends \
		ca-certificates \
		curl \
		dnsutils \
		ethtool \
		htop \
		i2c-tools \
		iperf3 \
		iw \
		jq \
		lsof \
		smartmontools \
		usbutils

	# Validate both DNS/TLS and the canonical Ubuntu ARM archive endpoint used by
	# Noble.  A failure aborts the image build.
	getent ahosts ports.ubuntu.com >/dev/null
	curl --fail --silent --show-error --location --head \
		--connect-timeout 15 --max-time 45 \
		https://ports.ubuntu.com/ubuntu-ports/dists/noble/InRelease >/dev/null

	install -D -m 0755 /tmp/overlay/usr/local/sbin/pcduino3b-selftest \
		/usr/local/sbin/pcduino3b-selftest

	cat >/etc/pcduino3b-build-info <<INFO
BOARD=pcDuino3B
ARMBIAN_BOARD=pcduino3
ARMBIAN_FAMILY=$LINUXFAMILY
UBUNTU_CODENAME=$RELEASE
KERNEL_POLICY=Armbian current (sunxi Linux 6.18.y)
ETHERNET_POLICY=A20 GMAC RGMII-ID + built-in STMMAC/DWMAC_SUNXI/REALTEK_PHY
BUILD_SOURCE_TEST=apt-get update + HTTPS ports.ubuntu.com Noble InRelease
INFO

	# Keep package indexes: they are useful for the first on-device source test.
	apt-get clean
}

Main "$@"
