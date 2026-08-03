# HP Pavilion x2 12-b: third-party USB-C PD charging patch (BIOS F.24)

> Experimental repair and interoperability research for one exact device
> configuration. It can permanently brick the device.

This project documents a narrowly scoped external-SPI patch that lets the EC
keep the charging gate enabled after a non-HP USB-C PD source is identified.
The HP "adapter is not compatible" warning may still appear; it is not the
charging-success criterion.

**Independent project.** It is not affiliated with or endorsed by HP, Anker,
Intel, ITE, Infineon, or Cypress. Read [NOTICE.md](NOTICE.md) and
[SECURITY.md](SECURITY.md) before using or redistributing anything.

## Exact supported configuration

- HP Pavilion x2 Detachable, SKU `T1F46EA#ABD`
- Mainboard `8181`, revision `42.25`
- HP/AMI BIOS `F.24` (2020-01-20)
- ITE IT8987 EC, GigaDevice GD25B64B 8 MiB SPI flash
- Tested charger: Anker `A2697`, direct C1 connection, 5 A e-marked cable

Do **not** run this on another board, BIOS version, or firmware image. The
scripts fail closed on platform, tool, sector, and post-write-hash mismatches,
but that does not remove the brick risk.

## Tested result

After the two-byte patch and a full EC power reset, the test device reported
stable Windows charging (`PowerOnline=True`, `Charging=True`,
`Discharging=False`) with about 15.95--15.98 W net battery charge rate. The EC
GPH4 charging-gate output was HIGH while the foreign-identity indication
remained set. See [TEST-RESULTS.md](TEST-RESULTS.md) for raw values, VID
analysis, and the limits of the measurement.

## Contents and provenance

This repository contains original PowerShell scripts, original UEFI source, a
reproducible binary built from that source, and documentation. It contains
**no** HP firmware, firmware dump, patched image, vendor updater, Intel FPT,
UEFI shell, `setup_var.efi`, schematic, or boardview.

The public scripts validate full SHA-256 sector states and structured boot
script fields. They do not embed copied vendor instruction or boot-script byte
sequences.

Third-party components must be obtained separately and lawfully; see
[third-party/README.md](third-party/README.md). Do not commit them to a fork or
GitHub release without independent redistribution rights.

## Procedure

Use [QUICKSTART.md](QUICKSTART.md) for the concise procedure.

1. Confirm the platform in elevated PowerShell:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\Check-Platform.ps1
   ```

2. Temporarily disable Secure Boot. From a FAT32 USB UEFI Shell, use
   `unlock-bios-lock.nsh`, confirm `Setup[0x550]=0x00` and
   `Setup[0xA5]=0x00`, then reboot.
3. Boot the USB drive again and run `patch-and-boot.nsh`. It applies a
   one-boot volatile-RAM patch, then starts Windows in the **same boot**.
4. In Windows, enter S3 sleep once and wake the device.
5. Run the flash-script preflight, then write only after
   `RESULT: PREFLIGHT READY`:

   ```powershell
   $fpt = 'C:\path\to\FPTW64.exe'
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\Flash-HP-PD-Patch.ps1 -FptPath $fpt
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\Flash-HP-PD-Patch.ps1 -FptPath $fpt -Proceed
   ```

6. On success, perform the mandatory full EC power reset: shut down, unplug
   all cables, disconnect the internal battery, hold power for 15--20 seconds,
   wait at least 60 seconds, then reconnect the battery.
7. Verify with `windows/Verify-Charging.ps1`; then restore BIOS Lock and
   Secure Boot. Keep the original sector backup in a safe place.

The patch script writes only SPI sector `0x20E000--0x20EFFF`. It accepts only
these sector states:

- Original SHA-256:
  `F03209480877C6163633545139E757DB337A68EA3AA6C3621DE9F6579AF705BC`
- Dual-patched SHA-256:
  `CD42181B6F2A6AA7BBB9290DF803A3967317F3EA8CC8C8F12724024D8DE5E7B6`

The two EC-relative target offsets are `0xE56C` and `0xE5E7`; each changes
from `0x4B` to `0x35`. This is not a generic HP charger unlock and does not
establish the actual USB-PD contract or the charger's Source VID/PID.

## Recovery

Never use another device's backup. Repeat the temporary unlock/one-boot/S3
sequence, then use `windows/Restore-HP-PD-Patch.ps1` with your own original
sector backup. Perform the same full battery-disconnect EC reset afterwards.

## Publication and legal notes

Publish only this sanitized repository, not the working directory used for
research. Do not publish vendor firmware, dumps, proprietary flash tools,
updater binaries, schematics, boardviews, or credentials. Hardware owners are
responsible for applicable law, licenses, warranty consequences, and
authorization. This project is not legal advice.

GitHub permits good-faith dual-use research but recommends a clear disclaimer
and a `SECURITY.md`; this repository provides both. See GitHub's
[dual-use policy](https://docs.github.com/en/site-policy/acceptable-use-policies/github-active-malware-or-exploits).
