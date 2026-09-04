# shellcheck shell=bash
# pcDuino3B Gigabit Ethernet kernel guarantees.
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
			# NAND experiments boot a dedicated DTB.  The normal SD DTB keeps
			# the controller disabled and is never modified at runtime.
			BOOT_FDT_FILE="allwinner/sun7i-a20-pcduino3b-nand-recovery.dtb"
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
	)

	# Armbian can call this hook before a kernel .config exists.
	[[ -f .config ]] || return 0

	# A20 GMAC + platform glue + Realtek RTL821x PHY support are all built-in.
	opts_y+=(
		CONFIG_STMMAC_ETH
		CONFIG_STMMAC_PLATFORM
		CONFIG_DWMAC_SUNXI
		CONFIG_REALTEK_PHY
	)
}
