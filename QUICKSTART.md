# Quick start

Only for an HP Pavilion x2 Detachable with board `8181` and BIOS `F.24`.
There is a full firmware-brick risk. Read `README.md` before starting.

1. Run `windows/Check-Platform.ps1` from an elevated PowerShell window.
2. Disable Secure Boot temporarily. Prepare a FAT32 USB drive containing a
   TianoCore UEFI Shell, `setup_var.efi`, and every file from `uefi/`.
3. Boot the USB drive, run `unlock-bios-lock.nsh`, confirm that both
   `Setup[0x550]` and `Setup[0xA5]` are `00`, then reboot.
4. Boot the USB drive again and run `patch-and-boot.nsh`. It must start Windows
   in the same boot; do not reboot between the patcher and Windows.
5. In Windows, enter real S3 sleep once and wake the device.
6. Run a preflight first in elevated PowerShell:

   ```powershell
   $fpt = 'C:\path\to\FPTW64.exe'
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\Flash-HP-PD-Patch.ps1 -FptPath $fpt
   ```

7. Only if the result is `RESULT: PREFLIGHT READY`, write in the same Windows
   session:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\Flash-HP-PD-Patch.ps1 -FptPath $fpt -Proceed
   ```

8. On `RESULT: FLASH SUCCESS`, shut down completely, unplug every cable,
   disconnect the internal battery, hold the power button for 15--20 seconds,
   wait at least 60 seconds, then reconnect the battery.
9. Connect the PD charger directly and run `windows/Verify-Charging.ps1`.
   Expected result: `RESULT=CHARGING`. The HP incompatible-adapter warning may
   still be displayed.
10. Preserve the original sector backup from `windows/output/` in more than one
    safe location. Restore BIOS Lock and Secure Boot after testing.

The physical battery/VSTBY reset is mandatory. Warm reboots do not load the
new EC code.
