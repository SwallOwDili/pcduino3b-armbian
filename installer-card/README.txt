pcDuino3B Armbian NAND automatic installer card

1. Power the board off.
2. Insert this SD card and power the board on normally.
3. A slow TX blink means NAND programming is active.
4. When the board powers off and TX stops, remove the SD card.
5. Power on again to test the new Armbian system from NAND.

Do not interrupt power while TX is blinking slowly.
A fast TX blink means failure. Power off, return the SD card to a computer,
and read logs/install.log plus state/FAILED.txt from the PCD3BINS volume.
logs/kernel.log and logs/journal-current-boot.log preserve the boot evidence.
state/SUCCESS.txt is written only after every NAND region passes readback.
