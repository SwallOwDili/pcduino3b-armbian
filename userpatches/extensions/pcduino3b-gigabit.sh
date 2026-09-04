# shellcheck shell=bash
# pcDuino3B Ethernet and onboard USB Wi-Fi kernel guarantees.
# Keep this file function-only: Armbian sources extension files into its build shell.

function extension_prepare_config__pcduino3b_profile_suffix() {
	case "${PCDUINO3B_IMAGE_PROFILE:-}" in
		nand-installer | nand-recovery)
			# Keep experimental NAND artifacts unmistakably separate from SD images.
			EXTRA_IMAGE_SUFFIXES+=("-${PCDUINO3B_IMAGE_PROFILE}")
			;;
	esac
}

function extension_prepare_config__pcduino3b_profile_dtb() {
	case "${PCDUINO3B_IMAGE_PROFILE:-}" in
		nand-installer | nand-recovery)
			# Keep the hardware-accepted base DTB on disk.  CI installs a
			# profile-specific overlay which U-Boot applies in memory; this is
			# the same path that remained network-stable on the physical board.
			BOOT_FDT_FILE="allwinner/sun7i-a20-pcduino3b.dtb"
			;;
	esac
}

function extension_prepare_config__pcduino3b_nand_uboot_artifacts() {
	case "${PCDUINO3B_IMAGE_PROFILE:-}" in
		nand-installer | nand-recovery)
			# Keep the normal SD boot binary and also package the two images needed
			# by the Allwinner BROM NAND layout.  The special SPL already contains
			# the required randomizer/ECC encoding.
			UBOOT_TARGET_MAP=';;u-boot-sunxi-with-spl.bin spl/sunxi-spl-with-ecc.bin:pcduino3b-nand-spl-with-ecc.bin u-boot-dtb.bin:pcduino3b-nand-u-boot.bin'
			;;
	esac
}

function extension_prepare_config__pcduino3b_packages() {
	local -a profile_packages=()

	[[ -n "${PCDUINO3B_EXTRA_PACKAGES:-}" ]] || return 0
	read -r -a profile_packages <<<"$PCDUINO3B_EXTRA_PACKAGES"
	add_packages_to_image "${profile_packages[@]}"
}

function custom_kernel_config__pcduino3b_gigabit_ethernet() {
	# Changing any of these options must invalidate Armbian's kernel-config cache.
	kernel_config_modifying_hashes+=(
		"CONFIG_STMMAC_ETH=y"
		"CONFIG_STMMAC_PLATFORM=y"
		"CONFIG_DWMAC_SUNXI=y"
		"CONFIG_REALTEK_PHY=y"
		"CONFIG_CFG80211=m"
		"CONFIG_MAC80211=m"
		"CONFIG_RTL8192CU=m"
		"CONFIG_RTL8XXXU=m"
		"CONFIG_USB=y"
		"CONFIG_USB_EHCI_HCD=y"
		"CONFIG_USB_EHCI_HCD_PLATFORM=y"
		"CONFIG_USB_OHCI_HCD=y"
		"CONFIG_USB_OHCI_HCD_PLATFORM=y"
	)

	# Armbian can call this hook before a kernel .config exists.
	[[ -f .config ]] || return 0

	# A20 GMAC + platform glue + Realtek RTL821x PHY support are all built-in.
	opts_y+=(
		CONFIG_STMMAC_ETH
		CONFIG_STMMAC_PLATFORM
		CONFIG_DWMAC_SUNXI
		CONFIG_REALTEK_PHY
		CONFIG_USB
		CONFIG_USB_EHCI_HCD
		CONFIG_USB_EHCI_HCD_PLATFORM
		CONFIG_USB_OHCI_HCD
		CONFIG_USB_OHCI_HCD_PLATFORM
	)

	# The physical target reports USB ID 0bda:8179 and is verified with the
	# in-tree rtl8xxxu driver.  Keep rtl8192cu too for 0bda:8176 board variants.
	opts_m+=(
		CONFIG_CFG80211
		CONFIG_MAC80211
		CONFIG_RTL8192CU
		CONFIG_RTL8XXXU
	)
}
