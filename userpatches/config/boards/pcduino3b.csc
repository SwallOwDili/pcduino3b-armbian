# Allwinner A20 dual core 1GiB SoC, pcDuino3B board identity.
BOARD_NAME="pcDuino3B"
BOARD_VENDOR="linksprite"
BOARDFAMILY="sun7i"
BOARD_MAINTAINER=""
BOOTCONFIG="Linksprite_pcDuino3_defconfig"
KERNEL_TARGET="current,edge,legacy"
KERNEL_TEST_TARGET="current"
BOOT_FDT_FILE="allwinner/sun7i-a20-pcduino3b.dtb"

# The board has an onboard USB Wi-Fi module.  Keep NetworkManager available
# even in the minimal recovery profiles so wireless setup does not require
# rebuilding or manually replacing the networking stack.
[[ -n "${NETWORKING_STACK:-}" ]] || NETWORKING_STACK="network-manager"

# pcDuino3B shares the A20 DRAM and base boot configuration with pcDuino3.
function post_config_uboot_target__extra_configs_for_pcduino3b() {
	display_alert "$BOARD" "set dram clock" "info"
	run_host_command_logged scripts/config --set-val CONFIG_DRAM_CLK "408"
	# Keep the shared upstream defconfig, but never expose its pcDuino3
	# control-DT identity from a pcDuino3B build.
	run_host_command_logged scripts/config --set-str CONFIG_DEFAULT_DEVICE_TREE "sun7i-a20-pcduino3b"
	run_host_command_logged scripts/config --set-str CONFIG_OF_LIST "sun7i-a20-pcduino3b"

	case "${PCDUINO3B_IMAGE_PROFILE:-}" in
		nand-installer | nand-recovery)
			display_alert "$BOARD" "enable NAND-capable U-Boot" "info"
			run_host_command_logged scripts/config --enable CONFIG_MTD
			run_host_command_logged scripts/config --enable CONFIG_MTD_RAW_NAND
			run_host_command_logged scripts/config --enable CONFIG_NAND_SUNXI
			run_host_command_logged scripts/config --enable CONFIG_CMD_NAND
			run_host_command_logged scripts/config --enable CONFIG_CMD_MTD
			run_host_command_logged scripts/config --enable CONFIG_CMD_MTDPARTS
			run_host_command_logged scripts/config --enable CONFIG_MTD_UBI
			run_host_command_logged scripts/config --enable CONFIG_CMD_UBI
			run_host_command_logged scripts/config --enable CONFIG_CMD_UBIFS
			run_host_command_logged scripts/config --set-val CONFIG_NAND_SUNXI_SPL_ECC_STRENGTH "64"
			run_host_command_logged scripts/config --set-val CONFIG_NAND_SUNXI_SPL_ECC_SIZE "1024"
			run_host_command_logged scripts/config --set-val CONFIG_NAND_SUNXI_SPL_USABLE_PAGE_SIZE "1024"
			run_host_command_logged scripts/config --set-val CONFIG_SYS_NAND_BLOCK_SIZE "0x200000"
			run_host_command_logged scripts/config --set-val CONFIG_SYS_NAND_PAGE_SIZE "8192"
			run_host_command_logged scripts/config --set-val CONFIG_SYS_NAND_OOBSIZE "640"
			run_host_command_logged scripts/config --set-val CONFIG_SYS_NAND_U_BOOT_OFFS "0x800000"
			;;
	esac
}
