echo HP Pavilion x2 F.24: current hidden lock values
setup_var.efi Setup:0x550
setup_var.efi Setup:0xA5
echo Writing BIOS Lock Setup[0x550] = 0x00
setup_var.efi Setup:0x550=0x00
echo Verify: BIOS Lock must be 0x00 and BIOS Guard must be 0x00
setup_var.efi Setup:0x550
setup_var.efi Setup:0xA5
echo Reboot now. The new lock value is consumed on the next boot.
