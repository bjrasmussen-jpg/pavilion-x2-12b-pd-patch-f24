# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Arla

param(
    [Parameter(Mandatory = $true)][string]$FptPath,
    [Parameter(Mandatory = $true)][string]$OriginalSectorPath,
    [string]$OutputDirectory,
    [switch]$Proceed
)

$ErrorActionPreference = 'Stop'
if (-not $Proceed) { throw 'Refusing to restore without -Proceed.' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $PSScriptRoot 'output' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path $OutputDirectory "restore-$stamp.log"
$lines = [System.Collections.Generic.List[string]]::new()

$expectedToolHashes = @{
    'FPTW64.exe'     = 'C926BEC646FCD216246E3EC64F38CBC07CBC2BE104CFC92B46A720EF3728E644'
    'fparts.txt'     = '9578122AD154539AE47E33450FA5E48466023CB6882A71CD99356219B8B25390'
    'Idrvdll32e.dll' = '71F13F4BC4E62664C27C7006500B3396D6BD4CAC70E50FAEE3512A39AC7E539A'
    'Pmxdll32e.dll'  = '5F408558D1D8AC2E8BB3136E43FEEBC247E219C2593D0FB28C7069FA4DFA4D5D'
}
$originalSectorHash = 'F03209480877C6163633545139E757DB337A68EA3AA6C3621DE9F6579AF705BC'
$dualSectorHash = 'CD42181B6F2A6AA7BBB9290DF803A3967317F3EA8CC8C8F12724024D8DE5E7B6'
$spiAddress = '0x20E000'
$sectorLength = '0x1000'

function Log([string]$Text) { $lines.Add($Text); Write-Output $Text }
function Invoke-Fpt([string]$Heading,[string[]]$Arguments) {
    Log $Heading
    Push-Location (Split-Path -Parent $FptPath)
    try { $output = & $FptPath @Arguments 2>&1; $code = $LASTEXITCODE }
    finally { Pop-Location }
    foreach ($entry in $output) { $lines.Add([string]$entry); Write-Output ([string]$entry) }
    Log "FPT exit code: $code"
    [pscustomobject]@{ ExitCode=$code }
}
function Read-SetupPolicy {
    if (-not ('HpPdRestoreSetupReader' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HpPdRestoreSetupReader {
    [DllImport("ntdll.dll")]
    public static extern int RtlAdjustPrivilege(int privilege, bool enable, bool currentThread, out bool enabled);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern uint GetFirmwareEnvironmentVariableExW(string name, string guid, byte[] buffer, uint size, out uint attributes);
}
'@
    }
    $previous = $false
    $status = [HpPdRestoreSetupReader]::RtlAdjustPrivilege(22,$true,$false,[ref]$previous)
    if ($status -ne 0) { throw 'Unable to obtain firmware-variable privilege.' }
    $buffer = New-Object byte[] 65536
    [uint32]$attributes = 0
    $length = [HpPdRestoreSetupReader]::GetFirmwareEnvironmentVariableExW('Setup','{EC87D643-EBA4-4BB5-A1E5-3F3E36B20DA9}',$buffer,[uint32]$buffer.Length,[ref]$attributes)
    if ($length -eq 0) { throw 'Unable to read Setup variable.' }
    [pscustomobject]@{ Length=$length; Attributes=$attributes; BiosGuard=$buffer[0xA5]; BiosLock=$buffer[0x550] }
}

try {
    Log ('Timestamp: {0:O}' -f (Get-Date))
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator rights are required.' }
    $bios = Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS'
    if ($bios.SystemManufacturer -ne 'HP' -or $bios.SystemProductName -ne 'HP Pavilion x2 Detachable' -or
        $bios.BaseBoardProduct -ne '8181' -or $bios.BIOSVersion -ne 'F.24') { throw 'Unsupported platform.' }
    if (Confirm-SecureBootUEFI) { throw 'Secure Boot is enabled.' }
    $setup = Read-SetupPolicy
    Log ('BIOS Lock=0x{0:X2}; BIOS Guard=0x{1:X2}' -f $setup.BiosLock,$setup.BiosGuard)
    if ($setup.Length -ne 3613 -or $setup.Attributes -ne 7 -or $setup.BiosLock -ne 0 -or $setup.BiosGuard -ne 0) {
        throw 'BIOS Lock/Firmware policy is not in the exact expected unlocked state.'
    }

    $FptPath = (Resolve-Path -LiteralPath $FptPath).Path
    $OriginalSectorPath = (Resolve-Path -LiteralPath $OriginalSectorPath).Path
    $toolDirectory = Split-Path -Parent $FptPath
    foreach ($name in $expectedToolHashes.Keys) {
        $path = if ($name -eq 'FPTW64.exe') { $FptPath } else { Join-Path $toolDirectory $name }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "$name is missing from the FPT directory." }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $expectedToolHashes[$name]) { throw "$name hash mismatch." }
    }
    if ((Get-FileHash $OriginalSectorPath -Algorithm SHA256).Hash -ne $originalSectorHash) { throw 'Original-sector hash mismatch.' }
    [byte[]]$originalBytes = [IO.File]::ReadAllBytes($OriginalSectorPath)
    if ($originalBytes.Length -ne 0x1000 -or $originalBytes[0x56C] -ne 0x4B -or $originalBytes[0x5E7] -ne 0x4B) {
        throw 'Original-sector size or target bytes do not match.'
    }

    $battery = Get-CimInstance Win32_Battery -OperationTimeoutSec 5
    $power = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -OperationTimeoutSec 5
    if (-not (@($power.PowerOnline) -contains $true)) { throw 'Stable external power is required for restore.' }
    if (($battery | Measure-Object EstimatedChargeRemaining -Minimum).Minimum -lt 60) { throw 'At least 60 percent battery is required.' }

    $before = Join-Path $OutputDirectory "sector-before-restore-$stamp.bin"
    $read = Invoke-Fpt 'READING CURRENT SECTOR' @('-D',$before,'-A',$spiAddress,'-L',$sectorLength)
    if ($read.ExitCode -ne 0) { throw 'Target read failed; repeat the pre-EBS/S3 unlock flow.' }
    if ((Get-FileHash $before -Algorithm SHA256).Hash -ne $dualSectorHash) { throw 'Current sector is not the exact dual-patch state.' }

    Log 'WRITING VERIFIED ORIGINAL 4-KiB SECTOR'
    $write = Invoke-Fpt 'ORIGINAL-SECTOR RESTORE' @('-F',$OriginalSectorPath,'-A',$spiAddress,'-L',$sectorLength)
    if ($write.ExitCode -ne 0) { throw 'Restore write failed. Do not power off until assessed.' }
    foreach ($number in 1,2) {
        $after = Join-Path $OutputDirectory "sector-after-restore-$stamp-$number.bin"
        $verify = Invoke-Fpt "POST-RESTORE READ $number" @('-D',$after,'-A',$spiAddress,'-L',$sectorLength)
        if ($verify.ExitCode -ne 0 -or (Get-FileHash $after -Algorithm SHA256).Hash -ne $originalSectorHash) {
            throw "Post-restore verification $number failed. Do not power off."
        }
    }
    Log 'RESULT: RESTORE SUCCESS - original sector written and read back twice.'
    Log 'Disconnect the internal battery for at least 60 seconds so the EC reloads the original code.'
}
catch { Log ("RESULT: ERROR - {0}" -f $_.Exception.Message); throw }
finally { $lines | Set-Content -LiteralPath $logPath -Encoding UTF8 }
