# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Arla

param(
    [ValidateRange(3, 30)][int]$SampleCount = 8,
    [ValidateRange(100, 5000)][int]$IntervalMs = 750
)

$ErrorActionPreference = 'Stop'
$samples = for ($i = 0; $i -lt $SampleCount; $i++) {
    $status = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -OperationTimeoutSec 5
    $battery = Get-CimInstance Win32_Battery -OperationTimeoutSec 5
    [pscustomobject]@{
        Time = Get-Date -Format 'HH:mm:ss'
        Percent = $battery.EstimatedChargeRemaining
        PowerOnline = [bool]$status.PowerOnline
        Charging = [bool]$status.Charging
        Discharging = [bool]$status.Discharging
        Voltage_mV = $status.Voltage
        ChargeRate_mW = $status.ChargeRate
        DischargeRate_mW = $status.DischargeRate
        Remaining_mWh = $status.RemainingCapacity
    }
    if ($i -lt $SampleCount - 1) { Start-Sleep -Milliseconds $IntervalMs }
}

$samples | Format-Table -AutoSize
$average = [math]::Round((($samples | Measure-Object ChargeRate_mW -Average).Average), 0)
$charging = @($samples | Where-Object { -not $_.PowerOnline -or -not $_.Charging -or $_.Discharging }).Count -eq 0 -and $average -gt 1000
'AverageChargeRate={0} mW' -f $average
'PD_SOURCE_VID=NOT_EXPOSED_BY_THIS_PLATFORM'
if ($charging) {
    'RESULT=CHARGING'
    exit 0
}
'RESULT=NOT_CHARGING'
exit 2
