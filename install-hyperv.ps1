<#
.SYNOPSIS
  Install Hyper-V and (optionally) create a virtual switch on Windows (Server / Client Pro+).

.DESCRIPTION
  This script automates enabling the Hyper-V role or Windows feature, validates virtualization support,
  and can create either an External vSwitch (bound to a host NIC) or an Internal NAT vSwitch.

  Supports:
  - Windows Server (Install-WindowsFeature)
  - Windows 10/11 Pro, Enterprise (Enable-WindowsOptionalFeature)
  - Detects unsupported SKUs (e.g., Windows Home) and warns
  - Optionally creates an External switch or an Internal NAT switch (configurable subnet)
  - Optionally reboots after install

.NOTES
  - Run as Administrator.
  - On client OS, you may be prompted to restart the machine to finish enabling Hyper-V.
  - The script uses built-in PowerShell cmdlets: Install-WindowsFeature / Enable-WindowsOptionalFeature / New-VMSwitch / New-NetNat, which are available when Hyper-V tools or networking modules are present.
  - On Windows Server the script uses Install-WindowsFeature; on clients it uses Enable-WindowsOptionalFeature.

.PARAMETER SwitchType
  "None" (default) | "External" | "InternalNAT"
.PARAMETER NetAdapterName
  Required if SwitchType is External: name of host NIC to bind the external vSwitch to.
.PARAMETER InternalSwitchName
  Name of internal NAT switch to create (default: "HV-NAT-Switch").
.PARAMETER InternalSubnet
  Subnet for internal NAT (default: 192.168.250.0/24).
.PARAMETER RebootNow
  Switch: reboot automatically if a reboot is required at the end.
.PARAMETER Force
  Switch: skip some confirmations.

.EXAMPLE
  .\install-hyperv.ps1 -SwitchType External -NetAdapterName "Ethernet" -RebootNow

  .\install-hyperv.ps1 -SwitchType InternalNAT -InternalSwitchName "NATSwitch" -InternalSubnet "192.168.100.0/24"

#>

param(
    [ValidateSet("None","External","InternalNAT")]
    [string]$SwitchType = "None",
    [string]$NetAdapterName = "",
    [string]$InternalSwitchName = "HV-NAT-Switch",
    [string]$InternalSubnet = "192.168.250.0/24",
    [switch]$RebootNow = $false,
    [switch]$Force = $false
)

function Assert-IsAdmin {
    $isAdmin = ([bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).Groups -match "S-1-5-32-544"))
    if (-not $isAdmin) {
        Write-Error "This script must be run as Administrator. Exiting."
        exit 2
    }
}

function Get-OsInfo {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $caption = $os.Caption
    $architecture = $os.OSArchitecture
    return @{ Caption = $caption; Architecture = $architecture }
}

function Is-VirtualizationEnabled {
    # Use systeminfo to detect "Virtualization Enabled In Firmware" (works on modern Windows)
    try {
        $sysInfo = systeminfo.exe 2>$null
        foreach ($line in $sysInfo) {
            if ($line -match "Virtualization Enabled In Firmware:\s*(Yes|No)") {
                return ($line -match "Yes")
            }
        }
    } catch {
        # Fallback: check SLAT/Hypervisor-capable flags via Get-WmiObject
    }
    # Last resort: attempt hypervisor support detection via CPU flags (not definitive)
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor
        if ($cpu.VirtualizationFirmwareEnabled -ne $null) {
            return [bool]$cpu.VirtualizationFirmwareEnabled
        }
    } catch { }
    return $null
}

function Install-HyperV-Server {
    Write-Host "Installing Hyper-V role and management tools (Server) ..."
    try {
        Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -Restart:$false -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Error "Failed to install Hyper-V on Server: $_"
        return $false
    }
}

function Install-HyperV-Client {
    Write-Host "Enabling Hyper-V feature on Client (Windows 10/11 Pro+). This may take a few minutes..."
    try {
        # Some systems use Microsoft-Hyper-V-All as the feature name; -All ensures dependencies are included
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All -NoRestart -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Error "Failed to enable Hyper-V feature on client OS: $_"
        return $false
    }
}

function Create-ExternalSwitch {
    param($Name, $AdapterName)
    Write-Host "Creating External vSwitch '$Name' bound to adapter '$AdapterName'..."
    try {
        # If a switch with that name exists, skip
        if (Get-VMSwitch -Name $Name -ErrorAction SilentlyContinue) {
            Write-Warning "VMSwitch '$Name' already exists. Skipping creation."
            return $true
        }
        New-VMSwitch -Name $Name -NetAdapterName $AdapterName -AllowManagementOS $true -ErrorAction Stop | Out-Null
        Write-Host "External vSwitch '$Name' created."
        return $true
    } catch {
        Write-Error "Failed to create external vSwitch: $_"
        return $false
    }
}

function Create-InternalNatSwitch {
    param($Name, $Subnet)
    Write-Host "Creating Internal vSwitch '$Name' with NAT subnet $Subnet ..."
    try {
        if (Get-VMSwitch -Name $Name -ErrorAction SilentlyContinue) {
            Write-Warning "VMSwitch '$Name' already exists. Skipping creation."
            return $true
        }
        New-VMSwitch -Name $Name -SwitchType Internal -ErrorAction Stop | Out-Null

        $ifName = "vEthernet ($Name)"
        # Extract network portion and prefix
        if ($Subnet -match "^(.+)\/(\d+)$") {
            $network = $matches[1]; $prefix = [int]$matches[2]
        } else {
            throw "InternalSubnet must be CIDR notation, e.g. 192.168.100.0/24"
        }

        # Choose host gateway as .1
        $hostIP = ($network -split '\.')[0..2] -join '.' + '.1'

        # Assign IP to host interface if not already assigned
        $existing = Get-NetIPAddress -InterfaceAlias $ifName -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-NetIPAddress -InterfaceAlias $ifName -IPAddress $hostIP -PrefixLength $prefix -ErrorAction Stop | Out-Null
            Write-Host "Assigned $hostIP/$prefix to $ifName"
        } else {
            Write-Host "Interface $ifName already has IP addresses configured. Leaving existing config."
        }

        # Create NAT
        $natName = "$Name-NAT"
        $existingNat = Get-NetNat -Name $natName -ErrorAction SilentlyContinue
        if (-not $existingNat) {
            New-NetNat -Name $natName -InternalIPInterfaceAddressPrefix $Subnet -ErrorAction Stop | Out-Null
            Write-Host "Created NAT '$natName' for $Subnet"
        } else {
            Write-Host "NAT '$natName' already exists."
        }
        return $true
    } catch {
        Write-Error "Failed to create internal NAT switch: $_"
        return $false
    }
}

### Script start ###
Assert-IsAdmin

$osInfo = Get-OsInfo
Write-Host "Detected OS: $($osInfo.Caption) ($($osInfo.Architecture))"

$virt = Is-VirtualizationEnabled
if ($virt -eq $null) {
    Write-Warning "Could not reliably determine whether virtualization is enabled in firmware. Please ensure virtualization (VT-x/AMD-V) is enabled in BIOS/UEFI."
} elseif (-not $virt) {
    Write-Warning "Virtualization appears to be disabled in firmware. Enable VT-x/AMD-V in your system BIOS/UEFI before installing Hyper-V."
    if (-not $Force) {
        Write-Host "Aborting due to disabled virtualization. Re-run with -Force to override."
        exit 3
    } else {
        Write-Warning "-Force specified: continuing despite virtualization apparently being disabled."
    }
}

# Check for Windows Home SKU (Home can't enable Hyper-V)
if ($osInfo.Caption -match "Home") {
    Write-Error "This appears to be Windows Home edition which does not support Hyper-V. Use Windows Pro/Enterprise or Windows Server."
    exit 4
}

$needReboot = $false
$installOk = $false

try {
    if ($osInfo.Caption -match "Server") {
        $installOk = Install-HyperV-Server
        # On Server, Install-WindowsFeature may set reboot required
        $pending = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\").RebootInProgress -ErrorAction SilentlyContinue
        # More robust check:
        if ((Get-WindowsFeature -Name Hyper-V).InstallState -eq "Installed") {
            Write-Host "Hyper-V role installed on Server."
        }
    } else {
        # Assume client OS
        $installOk = Install-HyperV-Client
        # Enabling optional features commonly requires reboot
        $needReboot = $true
    }
} catch {
    Write-Error "Installation attempt failed: $_"
    exit 5
}

if (-not $installOk) {
    Write-Error "Hyper-V installation failed. Inspect errors above."
    exit 6
}

# Load Hyper-V module (may be available after role install)
Import-Module Hyper-V -ErrorAction SilentlyContinue

# Switch creation if requested
if ($SwitchType -eq "External") {
    if ([string]::IsNullOrWhiteSpace($NetAdapterName)) {
        Write-Error "SwitchType External requires -NetAdapterName to be specified."
        exit 7
    }
    if (-not (Get-NetAdapter -Name $NetAdapterName -ErrorAction SilentlyContinue)) {
        Write-Error "Network adapter '$NetAdapterName' not found on host. Check adapter name with Get-NetAdapter."
        exit 8
    }
    if (-not (Create-ExternalSwitch -Name $InternalSwitchName -AdapterName $NetAdapterName)) {
        Write-Error "External vSwitch creation failed."
        exit 9
    }
} elseif ($SwitchType -eq "InternalNAT") {
    if (-not (Create-InternalNatSwitch -Name $InternalSwitchName -Subnet $InternalSubnet)) {
        Write-Error "Internal NAT vSwitch creation failed."
        exit 10
    }
} else {
    Write-Host "No virtual switch requested. You can create one later using New-VMSwitch."
}

# Final messaging
Write-Host ""
Write-Host "Hyper-V installation steps completed successfully."
if ($needReboot -or $RebootNow) {
    Write-Host "A reboot is recommended to complete the installation."
    if ($RebootNow) {
        Write-Host "Rebooting now..."
        Restart-Computer -Force
    } else {
        Write-Host "Please reboot the machine at your convenience."
    }
} else {
    Write-Host "No reboot required. You can start using Hyper-V now."
}

Write-Host "Summary:"
Write-Host "  OS: $($osInfo.Caption)"
Write-Host "  SwitchType: $SwitchType"
if ($SwitchType -eq "External") { Write-Host "  External adapter: $NetAdapterName; switch name: $InternalSwitchName" }
if ($SwitchType -eq "InternalNAT") { Write-Host "  Internal switch: $InternalSwitchName; subnet: $InternalSubnet" }
Write-Host "Done."
