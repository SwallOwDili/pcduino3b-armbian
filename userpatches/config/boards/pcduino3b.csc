# Allwinner A20 dual core 1GiB SoC, pcDuino3B board identity.
BOARD_NAME="pcDuino3B"
BOARD_VENDOR="linksprite"
BOARDFAMILY="sun7i"
BOARD_MAINTAINER=""
BOOTCONFIG="Linksprite_pcDuino3_defconfig"
KERNEL_TARGET="current,edge,legacy"
KERNEL_TEST_TARGET="current"
BOOT_FDT_FILE="allwinner/sun7i-a20-pcduino3b.dtb"

# pcDuino3B shares the A20 DRAM and base boot configuration with pcDuino3.
function post_config_uboot_target__extra_configs_for_pcduino3b() {
	display_alert "$BOARD" "set dram clock" "info"
	run_host_command_logged scripts/config --set-val CONFIG_DRAM_CLK "408"
}
