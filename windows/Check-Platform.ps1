# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Arla

param()

$ErrorActionPreference = 'Stop'

function Read-SetupVariable {
    if (-not ('HpPdSetupReader' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HpPdSetupReader {
    [DllImport("ntdll.dll")]
    public static extern int RtlAdjustPrivilege(int privilege, bool enable, bool currentThread, out bool enabled);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern uint GetFirmwareEnvironmentVariableExW(string name, string guid, byte[] buffer, uint size, out uint attributes);
}
'@
    }
    $previous = $false
    $status = [HpPdSetupReader]::RtlAdjustPrivilege(22, $true, $false, [ref]$previous)
    if ($status -ne 0) { throw ('SeSystemEnvironmentPrivilege failed: 0x{0:X8}' -f $status) }
    $buffer = New-Object byte[] 65536
    [uint32]$attributes = 0
    $length = [HpPdSetupReader]::GetFirmwareEnvironmentVariableExW(
        'Setup', '{EC87D643-EBA4-4BB5-A1E5-3F3E36B20DA9}', $buffer, [uint32]$buffer.Length, [ref]$attributes)
    if ($length -eq 0) { throw "Setup variable read failed: Win32 $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
    [pscustomobject]@{ Length=$length; Attributes=$attributes; BiosGuard=$buffer[0xA5]; BiosLock=$buffer[0x550] }
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script as administrator.'
}

$bios = Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS'
$supported = $bios.SystemManufacturer -eq 'HP' -and
             $bios.SystemProductName -eq 'HP Pavilion x2 Detachable' -and
             $bios.BaseBoardProduct -eq '8181' -and
             $bios.BIOSVersion -eq 'F.24'

[pscustomobject]@{
    Manufacturer = $bios.SystemManufacturer
    Product = $bios.SystemProductName
    SKU = $bios.SystemSKU
    Board = $bios.BaseBoardProduct
    BoardRevision = $bios.BaseBoardVersion
    BIOS = $bios.BIOSVersion
    BIOSDate = $bios.BIOSReleaseDate
    Supported = $supported
} | Format-List

$setup = Read-SetupVariable
'Setup length={0}; attributes=0x{1:X8}; BIOS Lock=0x{2:X2}; BIOS Guard=0x{3:X2}' -f $setup.Length,$setup.Attributes,$setup.BiosLock,$setup.BiosGuard
try { 'Secure Boot: {0}' -f (Confirm-SecureBootUEFI) } catch { 'Secure Boot: unavailable' }

$battery = Get-CimInstance Win32_Battery -OperationTimeoutSec 5
$power = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -OperationTimeoutSec 5
'Battery={0}%; PowerOnline={1}; Charging={2}; ChargeRate={3} mW' -f $battery.EstimatedChargeRemaining,$power.PowerOnline,$power.Charging,$power.ChargeRate

if (-not $supported) { throw 'RESULT=UNSUPPORTED_PLATFORM' }
'RESULT=SUPPORTED_PLATFORM'
