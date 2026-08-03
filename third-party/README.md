# Third-party components not included

This repository deliberately does not include Intel, HP, TianoCore, or
`setup_var.efi` binaries. Obtain them lawfully from their respective upstream
projects and comply with their licenses. Do not add them to a GitHub fork or
release unless you have redistribution rights.

## `setup_var.efi` 0.3.1

- Project: <https://github.com/datasone/setup_var.efi>
- Release: <https://github.com/datasone/setup_var.efi/releases/tag/0.3.1>
- Tested x86_64 file length: 101376 bytes
- Tested SHA-256:
  `CBE5777B61276D3F3506A28B34845326E92F6C171BFF59177E3912FE20F49840`
- Upstream license: MIT or Apache-2.0

## TianoCore EDK II UEFI Shell

- Project: <https://github.com/tianocore/edk2>
- Shell documentation: <https://www.tianocore.org/tianocore-wiki.github.io/platforms-packages/core-packages/shell_pkg.html>
- Tested `Shell.efi` length: 951744 bytes
- Tested SHA-256:
  `04C89F19EFEE2A22660FD4650FF9ADD88E962D102B1B713E535F4E32A07C5185`
- Place it on the FAT32 USB drive as `EFI/BOOT/BOOTX64.EFI`.

Another current 64-bit UEFI shell may work, but was not tested with this exact
workflow.

## Intel Flash Programming Tool

- Required: `FPTW64.exe` from a Skylake/CSME-v11-compatible Intel CSME System
  Tools v11 package obtained through a lawful source.
- Tested version: Intel FPT `11.8.70.3626`
- Tested `FPTW64.exe` SHA-256:
  `C926BEC646FCD216246E3EC64F38CBC07CBC2BE104CFC92B46A720EF3728E644`
- `fparts.txt` and the matching DLLs must be beside `FPTW64.exe`.

Also checked on the test device:

- `fparts.txt`: `9578122AD154539AE47E33450FA5E48466023CB6882A71CD99356219B8B25390`
- `Idrvdll32e.dll`: `71F13F4BC4E62664C27C7006500B3396D6BD4CAC70E50FAEE3512A39AC7E539A`
- `Pmxdll32e.dll`: `5F408558D1D8AC2E8BB3136E43FEEBC247E219C2593D0FB28C7069FA4DFA4D5D`

The Windows flash script refuses any other checked file hash.

## Zig (only to rebuild this project's EFI binary)

`uefi/PatchS3Fpr2.efi` is built from the included original C source. To rebuild
it, install Zig independently and run:

```powershell
.\uefi\build.ps1 -ZigExe C:\path\to\zig.exe
```
