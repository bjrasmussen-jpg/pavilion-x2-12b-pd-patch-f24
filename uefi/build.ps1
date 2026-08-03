# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Arla

param(
    [Parameter(Mandatory = $true)]
    [string]$ZigExe
)

$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Source = Join-Path $Here 'patch_s3_fpr2.c'
$Output = Join-Path $Here 'PatchS3Fpr2.efi'

& $ZigExe cc `
    -target x86_64-uefi `
    -O2 `
    -ffreestanding `
    -fno-builtin `
    -fno-stack-protector `
    -mno-red-zone `
    -nostdlib `
    -o $Output `
    $Source

if ($LASTEXITCODE -ne 0) {
    throw "zig cc failed with exit code $LASTEXITCODE"
}

Get-Item -LiteralPath $Output
Get-FileHash -Algorithm SHA256 -LiteralPath $Output
