<#
.SYNOPSIS
  Create an SMB share on the Hyper-V host to serve files to VMs over the network.

.DESCRIPTION
  Creates a host folder, creates an SMB share, and prints connection instructions.
  This requires the VM to have network connectivity to the host (e.g., via External vSwitch
  or Internal NAT where the host acts as gateway). This method is useful for Linux and Windows guests.

.PARAMETER ShareName
  SMB share name to create (e.g., "VMFiles").

.PARAMETER HostFolder
  Local folder on host to share (will be created if missing).

.PARAMETER AllowEveryone
  If true, grants Everyone Full access (insecure but convenient for labs). Default: $false.

.EXAMPLE
  .\create-host-smb-share.ps1 -ShareName "VMFiles" -HostFolder "C:\HyperV\Shared" -AllowEveryone
#>

param(
    [Parameter(Mandatory=$true)][string]$ShareName,
    [Parameter(Mandatory=$true)][string]$HostFolder,
    [switch]$AllowEveryone = $false
)

function Ensure-Admin {
    $isAdmin = ([bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).Groups -match "S-1-5-32-544"))
    if (-not $isAdmin) {
        Write-Error "This script must be run as Administrator."
        exit 1
    }
}
Ensure-Admin

if (-not (Test-Path $HostFolder)) {
    New-Item -ItemType Directory -Path $HostFolder -Force | Out-Null
}

# Create SMB share
if (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue) {
    Write-Warning "Share '$ShareName' already exists. Skipping creation."
} else {
    if ($AllowEveryone) {
        New-SmbShare -Name $ShareName -Path $HostFolder -FullAccess Everyone -ErrorAction Stop | Out-Null
        Write-Host "Created share \\$(hostname)\$ShareName with FullAccess for Everyone (INSECURE)."
    } else {
        New-SmbShare -Name $ShareName -Path $HostFolder -ErrorAction Stop | Out-Null
        Write-Host "Created share \\$(hostname)\$ShareName. You'll need valid host credentials to connect from guests."
    }
}

# Print instructions
$hostIP = (Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin Manual | Where-Object { $_.IPAddress -ne "127.0.0.1" } | Select-Object -First 1).IPAddress
if (-not $hostIP) { $hostIP = (Get-NetIPAddress -AddressFamily IPv4 | Select-Object -First 1).IPAddress }

Write-Host ""
Write-Host "Host share details:"
Write-Host "  Path: $HostFolder"
Write-Host "  SMB share: \\$(hostname)\$ShareName"
Write-Host "  Example connection (Windows guest):"
Write-Host "    net use Z: \\\\$hostIP\\$ShareName /user:HOST\\YourUser YourPassword"
Write-Host "  Example connection (Linux guest):"
Write-Host "    sudo mount -t cifs //${hostIP}/${ShareName} /mnt -o username=YourUser,password=YourPassword,vers=3.0"
Write-Host ""
Write-Host "Note: If using an Internal NAT switch, the host internal vEthernet interface IP is typically the gateway (e.g., 192.168.100.1). Use that IP if your host has multiple addresses."
