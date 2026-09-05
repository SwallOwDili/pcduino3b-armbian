#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

# shellcheck source=../userpatches/extensions/pcduino3b-gigabit.sh
source "$REPO_ROOT/userpatches/extensions/pcduino3b-gigabit.sh"

NETWORKING_STACK=""
# shellcheck source=../userpatches/config/boards/pcduino3b.csc
source "$REPO_ROOT/userpatches/config/boards/pcduino3b.csc"
[[ "$NETWORKING_STACK" == network-manager ]]

grep -Fxq iw "$REPO_ROOT/packages/common.txt"
grep -Fxq usbutils "$REPO_ROOT/packages/common.txt"

kernel_config_modifying_hashes=()
opts_y=()
opts_m=()

cd "$TEST_ROOT"
touch .config
custom_kernel_config__pcduino3b_gigabit_ethernet

for expected in \
	CONFIG_CFG80211=m \
	CONFIG_MAC80211=m \
	CONFIG_RTL8192CU=m \
	CONFIG_RTL8XXXU=m \
	CONFIG_USB=y \
	CONFIG_USB_EHCI_HCD=y \
	CONFIG_USB_EHCI_HCD_PLATFORM=y \
	CONFIG_USB_OHCI_HCD=y \
	CONFIG_USB_OHCI_HCD_PLATFORM=y; do
	printf '%s\n' "${kernel_config_modifying_hashes[@]}" | grep -Fxq "$expected"
done

for expected in \
	CONFIG_CFG80211 \
	CONFIG_MAC80211 \
	CONFIG_RTL8192CU \
	CONFIG_RTL8XXXU; do
	printf '%s\n' "${opts_m[@]}" | grep -Fxq "$expected"
done

for expected in \
	CONFIG_USB \
	CONFIG_USB_EHCI_HCD \
	CONFIG_USB_EHCI_HCD_PLATFORM \
	CONFIG_USB_OHCI_HCD \
	CONFIG_USB_OHCI_HCD_PLATFORM; do
	printf '%s\n' "${opts_y[@]}" | grep -Fxq "$expected"
done

echo 'pcduino3b Wi-Fi kernel config fixture: PASS'
