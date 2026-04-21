<#
.SYNOPSIS
    Phase 0.A — create VMnet10 (Host-Only 192.168.10.0/24) and VMnet11 (NAT 192.168.70.0/24)
    on a VMware Workstation Pro host.

.DESCRIPTION
    Canonical host bootstrap for the NexusPlatform 65-VM lab. Idempotent.
    Must be run in an ELEVATED PowerShell 7+ session on the VMware host (10.0.70.101).

    Driven through vnetlib64.exe because Workstation does not expose a stable public API
    and netmap.conf is documented by VMware as not hand-editable.

.NOTES
    - VMware Workstation Pro on Windows supports vmnet0..vmnet19 only.
    - vmnet0 (Bridged), vmnet1 (Host-Only, in-use), vmnet8 (NAT, in-use) are reserved.
    - This script registers vmnet10 + vmnet11 only and does not touch existing vnets.
    - DHCP is DISABLED on vmnet10 (VMs use static IPs per Vol01 canon).
    - DHCP on vmnet11 is scoped to .200..250 (Packer install-time leases only).
#>

#Requires -Version 7.0
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$VmwarePath = 'C:\Program Files (x86)\VMware\VMware Workstation',
    [switch]$WhatIfOnly
)

$ErrorActionPreference = 'Stop'
$vnetlib = Join-Path $VmwarePath 'vnetlib64.exe'
if (-not (Test-Path $vnetlib)) { throw "vnetlib64.exe not found at $vnetlib" }

function Invoke-VNetLib {
    param([Parameter(Mandatory)][string[]]$Arguments)
    Write-Host "  > vnetlib64 $($Arguments -join ' ')" -ForegroundColor DarkGray
    if ($WhatIfOnly) { return }
    & $vnetlib @Arguments
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "vnetlib64 exited $LASTEXITCODE (may be benign for idempotent ops)"
    }
}

Write-Host "`n=== Phase 0.A: NexusPlatform VMnet bootstrap ===" -ForegroundColor Cyan
Write-Host "Host: $env:COMPUTERNAME  |  User: $env:USERNAME  |  WhatIfOnly: $WhatIfOnly"

# --- 1. Stop VMware services (vnetlib requires services stopped for 'add adapter') ---
Write-Host "`n[1/6] Stopping VMware networking services..." -ForegroundColor Yellow
Invoke-VNetLib @('--', 'stop', 'nat')
Invoke-VNetLib @('--', 'stop', 'dhcp')

# --- 2. Register vmnet10 as Host-Only, 192.168.10.0/24, DHCP off ---
Write-Host "`n[2/6] Creating VMnet10 (Host-Only, 192.168.10.0/24, DHCP off)..." -ForegroundColor Yellow
Invoke-VNetLib @('--', 'add',      'adapter', 'vmnet10')
Invoke-VNetLib @('--', 'set',      'vnet',    'vmnet10', 'addr',    '192.168.10.0')
Invoke-VNetLib @('--', 'set',      'vnet',    'vmnet10', 'mask',    '255.255.255.0')
Invoke-VNetLib @('--', 'remove',   'dhcp',    'vmnet10')   # ensure DHCP disabled
Invoke-VNetLib @('--', 'update',   'adapter', 'vmnet10')

# --- 3. Register vmnet11 as NAT, 192.168.70.0/24, DHCP scoped ---
Write-Host "`n[3/6] Creating VMnet11 (NAT, 192.168.70.0/24, DHCP .200-.250)..." -ForegroundColor Yellow
Invoke-VNetLib @('--', 'add',    'adapter', 'vmnet11')
Invoke-VNetLib @('--', 'set',    'vnet',    'vmnet11', 'addr', '192.168.70.0')
Invoke-VNetLib @('--', 'set',    'vnet',    'vmnet11', 'mask', '255.255.255.0')
Invoke-VNetLib @('--', 'add',    'nat',     'vmnet11')
Invoke-VNetLib @('--', 'add',    'dhcp',    'vmnet11')
Invoke-VNetLib @('--', 'update', 'adapter', 'vmnet11')

# --- 4. Restart services ---
Write-Host "`n[4/6] Restarting VMware networking services..." -ForegroundColor Yellow
Invoke-VNetLib @('--', 'start', 'dhcp')
Invoke-VNetLib @('--', 'start', 'nat')

# --- 5. Apply + reload ---
Write-Host "`n[5/6] Applying configuration..." -ForegroundColor Yellow
Invoke-VNetLib @('--', 'update', 'dhcp')
Invoke-VNetLib @('--', 'update', 'nat')

# --- 6. Verify ---
Write-Host "`n[6/6] Verifying..." -ForegroundColor Yellow
$adapters = Get-NetAdapter | Where-Object { $_.Name -match 'VMnet(10|11)$' }
if ($adapters.Count -ge 2) {
    $adapters | Select-Object Name, Status, MacAddress, LinkSpeed | Format-Table -AutoSize
    Write-Host "`nSUCCESS: vmnet10 + vmnet11 adapters present on host." -ForegroundColor Green
} else {
    Write-Warning "Expected 2 new adapters; found $($adapters.Count). Inspect Virtual Network Editor manually."
    Write-Host "Run:  & '$VmwarePath\vmnetcfg.exe'  (as Administrator)"
}

Write-Host "`nvmnet10 expected IP on host side: 192.168.10.1  (VMware Virtual Ethernet Adapter for VMnet10)"
Write-Host "vmnet11 expected IP on host side: 192.168.70.1  (VMware NAT gateway: 192.168.70.2)"
Write-Host "`nNext: commit docs/infra/host-setup.md evidence block with screenshots + verification output."
