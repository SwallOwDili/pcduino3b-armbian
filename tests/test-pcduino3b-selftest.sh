#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELFTEST="$REPO_ROOT/userpatches/overlay/usr/local/sbin/pcduino3b-selftest"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p \
	"$TEST_ROOT/bin" \
	"$TEST_ROOT/etc" \
	"$TEST_ROOT/log" \
	"$TEST_ROOT/proc" \
	"$TEST_ROOT/real-dt/soc/ethernet@1c50000" \
	"$TEST_ROOT/sys/class/net/end0/phydev" \
	"$TEST_ROOT/sys/class/net/wlan0/device" \
	"$TEST_ROOT/sys/class/net/wlan0/wireless" \
	"$TEST_ROOT/sys/bus/usb/drivers/rtl8xxxu" \
	"$TEST_ROOT/sys/bus/mdio_bus/drivers/realtek"
ln -s "$TEST_ROOT/real-dt" "$TEST_ROOT/proc/device-tree"
ln -s "$TEST_ROOT/sys/bus/mdio_bus/drivers/realtek" "$TEST_ROOT/sys/class/net/end0/phydev/driver"
ln -s "$TEST_ROOT/sys/bus/usb/drivers/rtl8xxxu" "$TEST_ROOT/sys/class/net/wlan0/device/driver"

printf 'LinkSprite pcDuino3B\0' >"$TEST_ROOT/real-dt/model"
printf 'rgmii-id\0' >"$TEST_ROOT/real-dt/soc/ethernet@1c50000/phy-mode"
printf '1\n' >"$TEST_ROOT/sys/class/net/end0/type"
printf '1\n' >"$TEST_ROOT/sys/class/net/wlan0/type"
printf 'RTL8211E Gigabit Ethernet\n' >"$TEST_ROOT/sys/class/net/end0/phydev/name"
printf 'DRIVER=realtek\n' >"$TEST_ROOT/sys/class/net/end0/phydev/uevent"
printf 'DRIVER=rtl8xxxu\nPRODUCT=bda/8179/0\n' >"$TEST_ROOT/sys/class/net/wlan0/device/uevent"
printf 'pcduino3b\n' >"$TEST_ROOT/etc/hostname"
printf '127.0.0.1 localhost\n127.0.1.1 pcduino3b\n' >"$TEST_ROOT/etc/hosts"
printf 'VERSION_CODENAME=noble\n' >"$TEST_ROOT/etc/os-release"
printf 'BOARD=pcduino3b\nBOARD_NAME="pcDuino3B"\n' >"$TEST_ROOT/etc/armbian-release"
printf 'BOARD=pcDuino3B\nARMBIAN_BOARD=pcduino3b\nARMBIAN_FAMILY=sunxi\nUBUNTU_CODENAME=noble\n' \
	>"$TEST_ROOT/etc/pcduino3b-build-info"

cat >"$TEST_ROOT/bin/uname" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
	-r) echo '6.18.49-current-sunxi' ;;
	-m) echo 'armv7l' ;;
	*) echo 'Linux 6.18.49-current-sunxi armv7l GNU/Linux' ;;
esac
MOCK
cat >"$TEST_ROOT/bin/dpkg" <<'MOCK'
#!/usr/bin/env bash
[[ "$1" == --print-architecture ]] && echo armhf
MOCK
cat >"$TEST_ROOT/bin/hostname" <<'MOCK'
#!/usr/bin/env bash
echo pcduino3b
MOCK
cat >"$TEST_ROOT/bin/hostnamectl" <<'MOCK'
#!/usr/bin/env bash
echo pcduino3b
MOCK
cat >"$TEST_ROOT/bin/ip" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
	'-4 route show default') echo 'default via 192.0.2.1 dev end0 proto dhcp' ;;
	'route') echo 'default via 192.0.2.1 dev end0 proto dhcp' ;;
	*) exit 0 ;;
esac
MOCK
cat >"$TEST_ROOT/bin/ethtool" <<'MOCK'
#!/usr/bin/env bash
if [[ "${1:-}" == -i ]]; then
	echo 'driver: st_gmac'
	exit 0
fi
cat <<'OUT'
Settings for end0:
	Speed: 1000Mb/s
	Duplex: Full
	Link detected: yes
OUT
MOCK
cat >"$TEST_ROOT/bin/dmesg" <<'MOCK'
#!/usr/bin/env bash
echo 'stmmaceth 1c50000.ethernet end0: PHY [stmmac-0:01] driver [RTL8211E Gigabit Ethernet]'
echo 'usb 2-1: rtl8xxxu loading rtlwifi/rtl8188eufw.bin'
echo 'sunxi-ahci 1c18000.sata: controller initialized'
MOCK
cat >"$TEST_ROOT/bin/iw" <<'MOCK'
#!/usr/bin/env bash
if [[ "$*" == 'dev wlan0 scan' ]]; then
	echo 'BSS 00:11:22:33:44:55(on wlan0)'
	exit 0
fi
exit 0
MOCK
cat >"$TEST_ROOT/bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
[[ "${1:-}" == is-active ]] && exit 0
exit 0
MOCK
cat >"$TEST_ROOT/bin/timedatectl" <<'MOCK'
#!/usr/bin/env bash
[[ "$*" == *NTPSynchronized* ]] && echo yes
exit 0
MOCK

for command_name in apt-get curl df findmnt free getent lscpu lsblk lsusb uptime; do
	ln -s /usr/bin/true "$TEST_ROOT/bin/$command_name"
done
find "$TEST_ROOT/bin" -type f -exec chmod +x {} +

OUTPUT="$TEST_ROOT/output.txt"
PATH="$TEST_ROOT/bin:$PATH" \
	PCDUINO3B_PROC_DT_ROOT="$TEST_ROOT/proc/device-tree" \
	PCDUINO3B_SYS_CLASS_NET="$TEST_ROOT/sys/class/net" \
	PCDUINO3B_ETC_ROOT="$TEST_ROOT/etc" \
	PCDUINO3B_LOG_DIR="$TEST_ROOT/log" \
	bash "$SELFTEST" --skip-apt >"$OUTPUT"

grep -Fq '[PASS] device tree model identifies LinkSprite pcDuino3B' "$OUTPUT"
grep -Fq '[PASS] /etc/armbian-release BOARD is pcduino3b' "$OUTPUT"
grep -Fq '[PASS] /etc/pcduino3b-build-info ARMBIAN_BOARD is pcduino3b' "$OUTPUT"
grep -Fq '[PASS] GMAC device tree uses rgmii-id' "$OUTPUT"
grep -Fq 'Ethernet interface: end0' "$OUTPUT"
grep -Fq '[PASS] RTL8211E PHY is bound' "$OUTPUT"
grep -Fq '[PASS] Ethernet negotiated 1000Mb/s Full Duplex' "$OUTPUT"
grep -Fq '[PASS] onboard Realtek Wi-Fi is bound to rtl8xxxu' "$OUTPUT"
grep -Fq '[PASS] Wi-Fi scan completed (1 BSS entries)' "$OUTPUT"
grep -Fq '[PASS] NetworkManager is active for Wi-Fi configuration' "$OUTPUT"
grep -Fq 'FAIL=0' "$OUTPUT"

rm "$TEST_ROOT/sys/class/net/end0/phydev/name"
OUTPUT_WITHOUT_PHY_NAME="$TEST_ROOT/output-without-phy-name.txt"
PATH="$TEST_ROOT/bin:$PATH" \
	PCDUINO3B_PROC_DT_ROOT="$TEST_ROOT/proc/device-tree" \
	PCDUINO3B_SYS_CLASS_NET="$TEST_ROOT/sys/class/net" \
	PCDUINO3B_ETC_ROOT="$TEST_ROOT/etc" \
	PCDUINO3B_LOG_DIR="$TEST_ROOT/log" \
	bash "$SELFTEST" --skip-apt >"$OUTPUT_WITHOUT_PHY_NAME" 2>&1

grep -Fq '[PASS] RTL8211E PHY is bound' "$OUTPUT_WITHOUT_PHY_NAME"
grep -Fq 'FAIL=0' "$OUTPUT_WITHOUT_PHY_NAME"
if grep -Fq 'No such file or directory' "$OUTPUT_WITHOUT_PHY_NAME"; then
	echo 'selftest emitted a missing PHY name error' >&2
	exit 1
fi

echo 'pcduino3b-selftest fixture: PASS'
