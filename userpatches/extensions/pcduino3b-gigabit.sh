# pcDuino3B Gigabit Ethernet kernel guarantees.
# Keep this file function-only: Armbian sources extension files into its build shell.

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
