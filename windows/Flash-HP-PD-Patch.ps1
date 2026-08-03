# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Arla

param(
    [Parameter(Mandatory = $true)]
    [string]$FptPath,
    [string]$OutputDirectory,
    [switch]$Proceed,
    [switch]$AllowBatteryPower
)

$ErrorActionPreference = 'Stop'
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $PSScriptRoot 'output' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path $OutputDirectory "flash-$stamp.log"
$lines = [System.Collections.Generic.List[string]]::new()

$expectedToolHashes = @{
    'FPTW64.exe'     = 'C926BEC646FCD216246E3EC64F38CBC07CBC2BE104CFC92B46A720EF3728E644'
    'fparts.txt'     = '9578122AD154539AE47E33450FA5E48466023CB6882A71CD99356219B8B25390'
    'Idrvdll32e.dll' = '71F13F4BC4E62664C27C7006500B3396D6BD4CAC70E50FAEE3512A39AC7E539A'
    'Pmxdll32e.dll'  = '5F408558D1D8AC2E8BB3136E43FEEBC247E219C2593D0FB28C7069FA4DFA4D5D'
}
$originalSectorHash = 'F03209480877C6163633545139E757DB337A68EA3AA6C3621DE9F6579AF705BC'
$onePatchSectorHash = '7FFFDF10C91251E94684166B0CD4747A2846F18219A2A879D4BEA2372372A14D'
$dualSectorHash = 'CD42181B6F2A6AA7BBB9290DF803A3967317F3EA8CC8C8F12724024D8DE5E7B6'
$spiAddress = '0x20E000'
$sectorLength = '0x1000'
$secondPatchOffset = 0x56C
$firstPatchOffset = 0x5E7

function Log([string]$Text) {
    $lines.Add($Text)
    Write-Output $Text
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Administrator rights are required.'
    }
}

function Assert-Platform {
    $bios = Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS'
    Log ('Platform: {0}; SKU={1}; board={2}/{3}; BIOS={4} ({5})' -f
        $bios.SystemProductName,$bios.SystemSKU,$bios.BaseBoardProduct,$bios.BaseBoardVersion,$bios.BIOSVersion,$bios.BIOSReleaseDate)
    if ($bios.SystemManufacturer -ne 'HP' -or
        $bios.SystemProductName -ne 'HP Pavilion x2 Detachable' -or
        $bios.BaseBoardProduct -ne '8181' -or
        $bios.BIOSVersion -ne 'F.24') {
        throw 'Unsupported platform. Expected HP Pavilion x2 Detachable, board 8181, BIOS F.24.'
    }
}

function Read-SetupPolicy {
    if (-not ('HpPdFlashSetupReader' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HpPdFlashSetupReader {
    [DllImport("ntdll.dll")]
    public static extern int RtlAdjustPrivilege(int privilege, bool enable, bool currentThread, out bool enabled);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern uint GetFirmwareEnvironmentVariableExW(string name, string guid, byte[] buffer, uint size, out uint attributes);
}
'@
    }
    $previous = $false
    $status = [HpPdFlashSetupReader]::RtlAdjustPrivilege(22, $true, $false, [ref]$previous)
    if ($status -ne 0) { throw ('Cannot enable firmware-variable privilege: 0x{0:X8}' -f $status) }
    $buffer = New-Object byte[] 65536
    [uint32]$attributes = 0
    $length = [HpPdFlashSetupReader]::GetFirmwareEnvironmentVariableExW(
        'Setup','{EC87D643-EBA4-4BB5-A1E5-3F3E36B20DA9}',$buffer,[uint32]$buffer.Length,[ref]$attributes)
    if ($length -eq 0) { throw "Setup variable read failed: Win32 $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
    [pscustomobject]@{ Length=$length; Attributes=$attributes; BiosGuard=$buffer[0xA5]; BiosLock=$buffer[0x550] }
}

function Invoke-Fpt([string]$Heading, [string[]]$Arguments) {
    Log $Heading
    Push-Location (Split-Path -Parent $FptPath)
    try {
        $output = & $FptPath @Arguments 2>&1
        $code = $LASTEXITCODE
    }
    finally { Pop-Location }
    foreach ($entry in $output) {
        $lines.Add([string]$entry)
        Write-Output ([string]$entry)
    }
    Log "FPT exit code: $code"
    [pscustomobject]@{ ExitCode=$code; Output=$output }
}

function Assert-Power {
    $battery = Get-CimInstance Win32_Battery -OperationTimeoutSec 5
    $status = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -OperationTimeoutSec 5
    $online = @($status.PowerOnline) -contains $true
    $percent = ($battery | Measure-Object EstimatedChargeRemaining -Minimum).Minimum
    Log "PowerOnline=$online; battery=$percent percent; AllowBatteryPower=$AllowBatteryPower"
    if ($online -and $percent -lt 60) { throw 'At least 60 percent battery is required.' }
    if (-not $online -and -not $AllowBatteryPower) {
        throw 'Stable external power is required. Use -AllowBatteryPower only after accepting the brick risk.'
    }
    if (-not $online -and $percent -lt 85) { throw 'Battery-only flashing requires at least 85 percent.' }
}

try {
    Log ('Timestamp: {0:O}' -f (Get-Date))
    Log 'Operation: fail-closed HP Pavilion x2 F.24 dual EC gate patch'
    Assert-Administrator
    Assert-Platform

    try {
        if (Confirm-SecureBootUEFI) { throw 'Secure Boot is enabled.' }
    }
    catch [System.PlatformNotSupportedException] { throw 'Unable to verify Secure Boot state.' }

    $setup = Read-SetupPolicy
    Log ('Setup: length={0}; attributes=0x{1:X8}; BIOS Lock=0x{2:X2}; BIOS Guard=0x{3:X2}' -f
        $setup.Length,$setup.Attributes,$setup.BiosLock,$setup.BiosGuard)
    if ($setup.Length -ne 3613 -or $setup.Attributes -ne 0x00000007 -or
        $setup.BiosLock -ne 0x00 -or $setup.BiosGuard -ne 0x00) {
        throw 'Unexpected Setup policy. BIOS Lock and BIOS Guard must both be 0x00.'
    }

    $FptPath = (Resolve-Path -LiteralPath $FptPath).Path
    $toolDirectory = Split-Path -Parent $FptPath
    foreach ($name in $expectedToolHashes.Keys) {
        $path = if ($name -eq 'FPTW64.exe') { $FptPath } else { Join-Path $toolDirectory $name }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "$name is missing from the FPT directory." }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $expectedToolHashes[$name]) {
            throw "$name hash mismatch."
        }
    }

    $before = Join-Path $OutputDirectory "sector-before-$stamp.bin"
    $candidate = Join-Path $OutputDirectory "sector-dual-candidate-$stamp.bin"
    $read = Invoke-Fpt 'READING TARGET SECTOR (NO WRITE)' @('-D',$before,'-A',$spiAddress,'-L',$sectorLength)
    if ($read.ExitCode -ne 0) {
        throw 'Target read failed. If FPT reports Error 316, repeat the pre-EBS patch and S3 wake sequence.'
    }
    if ((Get-Item -LiteralPath $before).Length -ne 0x1000) { throw 'Target sector length is not 4096 bytes.' }
    $beforeHash = (Get-FileHash -LiteralPath $before -Algorithm SHA256).Hash
    Log "Current sector SHA256=$beforeHash"

    [byte[]]$bytes = [IO.File]::ReadAllBytes($before)
    if ($beforeHash -eq $dualSectorHash) {
        if ($bytes[$secondPatchOffset] -ne 0x35 -or $bytes[$firstPatchOffset] -ne 0x35) {
            throw 'Dual-patch hash matched but target bytes did not.'
        }
        Log 'RESULT: ALREADY PATCHED - exact dual-patch sector is present; no write performed.'
        return
    }
    if ($beforeHash -ne $originalSectorHash -and $beforeHash -ne $onePatchSectorHash) {
        throw 'Unknown sector hash. Refusing to create or flash a candidate.'
    }

    # The accepted whole-sector SHA-256 values are the complete context check.
    # Do not embed vendor firmware instruction sequences in this public tool.
    if ($beforeHash -eq $originalSectorHash -and
        ($bytes[$secondPatchOffset] -ne 0x4B -or $bytes[$firstPatchOffset] -ne 0x4B)) {
        throw 'Original target-byte state mismatch.'
    }
    if ($beforeHash -eq $onePatchSectorHash -and
        ($bytes[$secondPatchOffset] -ne 0x4B -or $bytes[$firstPatchOffset] -ne 0x35)) {
        throw 'Intermediate target-byte state mismatch.'
    }

    [byte[]]$patched = $bytes.Clone()
    $patched[$secondPatchOffset] = 0x35
    $patched[$firstPatchOffset] = 0x35
    [IO.File]::WriteAllBytes($candidate,$patched)
    $candidateHash = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash
    Log "Candidate SHA256=$candidateHash"
    if ($candidateHash -ne $dualSectorHash) { throw 'Generated candidate hash mismatch.' }

    $differenceOffsets = [System.Collections.Generic.List[int]]::new()
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -ne $patched[$i]) { $differenceOffsets.Add($i) }
    }
    $expectedDiffCount = if ($beforeHash -eq $originalSectorHash) { 2 } else { 1 }
    if ($differenceOffsets.Count -ne $expectedDiffCount -or
        -not $differenceOffsets.Contains($secondPatchOffset) -or
        ($beforeHash -eq $originalSectorHash -and -not $differenceOffsets.Contains($firstPatchOffset))) {
        throw 'Candidate differs at unexpected offsets.'
    }
    Log ('Differences from current sector: {0}' -f (($differenceOffsets | ForEach-Object { '0x{0:X3}' -f $_ }) -join ', '))

    if (-not $Proceed) {
        Log 'RESULT: PREFLIGHT READY - candidate created and verified; no flash write performed.'
        Log 'Re-run with -Proceed in this same unlocked Windows session.'
        return
    }

    Assert-Power
    if ($beforeHash -eq $originalSectorHash) {
        $originalBackup = Join-Path $OutputDirectory "sector-original-$stamp.bin"
        Copy-Item -LiteralPath $before -Destination $originalBackup
        Log "KEEP THIS ORIGINAL BACKUP: $originalBackup"
    }
    else {
        Log 'WARNING: current state already contained the first patch; this run cannot create a pristine original backup.'
    }

    Log 'TARGETED 4-KiB FLASH STARTING NOW'
    $write = Invoke-Fpt 'WRITING DUAL-PATCH SECTOR' @('-F',$candidate,'-A',$spiAddress,'-L',$sectorLength)
    if ($write.ExitCode -ne 0) { throw 'FPT write failed. Do not power off until the result has been assessed.' }

    foreach ($number in 1,2) {
        $verifyPath = Join-Path $OutputDirectory "sector-after-$stamp-$number.bin"
        $verify = Invoke-Fpt "POST-WRITE READ $number" @('-D',$verifyPath,'-A',$spiAddress,'-L',$sectorLength)
        if ($verify.ExitCode -ne 0) { throw "Post-write read $number failed. Do not power off." }
        $verifyHash = (Get-FileHash -LiteralPath $verifyPath -Algorithm SHA256).Hash
        Log "Post-write read $number SHA256=$verifyHash"
        if ($verifyHash -ne $dualSectorHash) { throw "Post-write read $number hash mismatch. Do not power off." }
    }

    Log 'RESULT: FLASH SUCCESS - both one-byte patches were written and read back twice.'
    Log 'NEXT REQUIRED STEP: shut down, unplug all power, disconnect the internal battery, hold power 15-20 seconds, wait at least 60 seconds, reconnect.'
}
catch {
    Log ("RESULT: ERROR - {0}" -f $_.Exception.Message)
    throw
}
finally {
    $lines | Set-Content -LiteralPath $logPath -Encoding UTF8
}
