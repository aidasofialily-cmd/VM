<#
.SYNOPSIS
  Create one or more Hyper-V virtual machines, optionally using differencing disks from a generalized base image.

.DESCRIPTION
  This script automates VM creation on Hyper-V. It supports:
  - Creating an Internal NAT switch (optional)
  - Creating VMs that use either:
      a) A parent generalized VHDX (differencing disks) -- fast cloning (recommended for Windows)
      b) Newly created dynamically expanding VHDX files (from scratch)
  - Setting memory, processors, generation, checkpointing, and network connection
  - Starting the VMs at the end

  NOTE: For Windows guests it's recommended to have a generalized (sysprep'd) base VHDX.
  For Linux guests, prepare a template VHDX or use cloud-init mechanisms (not included here).

.PARAMETER VMCount
  Number of VMs to create.

.PARAMETER VMNamePrefix
  Prefix used for VM names. VMs will be named <prefix>-1, <prefix>-2, ...

.PARAMETER BaseVhdxPath
  Path to a generalized (sysprep'd) parent VHDX (use with -UseDifferencingDisk). If not provided and -UseDifferencingDisk is true, script errors.

.PARAMETER UseDifferencingDisk
  Switch: if set, script creates differencing disks against BaseVhdxPath. Recommended for Windows base images.

.PARAMETER SwitchName
  Name of the Hyper-V virtual switch to connect VMs to. If it does not exist and -CreateInternalSwitch is set, an Internal NAT switch will be created.

.PARAMETER CreateInternalSwitch
  Switch: if set and the SwitchName does not exist, the script will create an internal NAT switch and set up NAT on host subnet 192.168.100.0/24 (adjustable in script).

.PARAMETER MemoryStartupMB
  Startup RAM in MB (default 4096).

.PARAMETER ProcessorCount
  Number of virtual processors (default 2).

.PARAMETER DiskSizeGB
  Size of new VHDX if not using differencing disk (default 60).

.PARAMETER Generation
  VM generation: 1 or 2 (default 2).

.PARAMETER VMPath
  Folder where VM files (VHDX) will be stored (default: C:\HyperV\VMs).

.PARAMETER AdminPassword
  Optional: plain-text password to set for the local Administrator account using PowerShell Direct (only works if guest is Windows and supports PowerShell Direct). If omitted no attempt to set a password is made.

.EXAMPLE
  .\create-vms.ps1 -VMCount 3 -VMNamePrefix "web" -UseDifferencingDisk -BaseVhdxPath "C:\Images\WinServ2022_gen.vhdx" -SwitchName "NATSwitch" -CreateInternalSwitch

#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
param(
    [int]$VMCount = 1,
    [string]$VMNamePrefix = "hvvm",
    [string]$BaseVhdxPath = "",
    [switch]$UseDifferencingDisk = $false,
    [string]$SwitchName = "NATSwitch",
    [switch]$CreateInternalSwitch = $true,
    [int]$MemoryStartupMB = 4096,
    [int]$ProcessorCount = 2,
    [int]$DiskSizeGB = 60,
    [ValidateSet(1,2)]
    [int]$Generation = 2,
    [string]$VMPath = "C:\HyperV\VMs",
    [string]$AdminPassword = ""
)

function Ensure-HyperVModule {
    if (-not (Get-Module -ListAvailable -Name Hyper-V)) {
        Write-Error "Hyper-V PowerShell module not found. Please enable the Hyper-V role and run this script as Administrator on a Hyper-V host."
        exit 1
    }
}

function Ensure-VMSwitch {
    param($Name, $CreateInternal)
    $existing = Get-VMSwitch -Name $Name -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Verbose "Found existing vSwitch '$Name'."
        return $true
    }

    if ($CreateInternal) {
        Write-Host "Creating internal switch '$Name' and configuring NAT on 192.168.100.0/24..."
        New-VMSwitch -Name $Name -SwitchType Internal | Out-Null
        # Wait a bit so the interface appears
        Start-Sleep -Seconds 2
        $ifName = "vEthernet ($Name)"
        # Assign host IP
        $ip = "192.168.100.1"
        $prefix = 24
        # Remove any existing conflicting IP on that interface
        $existingIP = Get-NetIPAddress -InterfaceAlias $ifName -ErrorAction SilentlyContinue
        if ($existingIP) {
            Write-Verbose "Interface $ifName already has IP addresses. Skipping IP assignment."
        } else {
            New-NetIPAddress -IPAddress $ip -PrefixLength $prefix -InterfaceAlias $ifName -ErrorAction Stop
        }

        # Create NAT if not exists
        $natName = "$Name-NAT"
        $existingNat = Get-NetNat -Name $natName -ErrorAction SilentlyContinue
        if (-not $existingNat) {
            New-NetNat -Name $natName -InternalIPInterfaceAddressPrefix "192.168.100.0/24" | Out-Null
        }
        return $true
    } else {
        Write-Error "Virtual switch '$Name' does not exist. Either create it manually or run with -CreateInternalSwitch to auto-create an internal NAT switch."
        return $false
    }
}

function New-DifferencingVhd {
    param($ParentPath, $ChildPath)
    if (-not (Test-Path $ParentPath)) {
        throw "Parent VHDX '$ParentPath' not found."
    }
    Write-Host "Creating differencing disk: $ChildPath -> parent $ParentPath"
    New-VHD -Path $ChildPath -ParentPath $ParentPath -Differencing -ErrorAction Stop | Out-Null
}

# Begin script
Ensure-HyperVModule

# normalize paths
$VMPath = (Resolve-Path -Path $VMPath).Path
if (-not (Test-Path $VMPath)) {
    New-Item -ItemType Directory -Path $VMPath -Force | Out-Null
}

# Ensure switch
if (-not (Ensure-VMSwitch -Name $SwitchName -CreateInternal:$CreateInternalSwitch)) {
    exit 1
}

for ($i = 1; $i -le $VMCount; $i++) {
    $vmName = "$VMNamePrefix-$i"
    $vmDir = Join-Path $VMPath $vmName
    if (-not (Test-Path $vmDir)) { New-Item -Path $vmDir -ItemType Directory | Out-Null }

    $vhdPath = ""

    if ($UseDifferencingDisk) {
        if ([string]::IsNullOrWhiteSpace($BaseVhdxPath)) {
            Write-Error "UseDifferencingDisk specified but BaseVhdxPath is empty. Exiting."
            exit 1
        }
        $childVhd = Join-Path $vmDir "$vmName-diff.vhdx"
        New-DifferencingVhd -ParentPath $BaseVhdxPath -ChildPath $childVhd
        $vhdPath = $childVhd
    } else {
        $vhdPath = Join-Path $vmDir "$vmName.vhdx"
        if (Test-Path $vhdPath) {
            Write-Warning "VHD path $vhdPath already exists; skipping New-VHD creation."
        } else {
            Write-Host "Creating new dynamically expanding VHDX: $vhdPath ($DiskSizeGB GB)"
            New-VHD -Path $vhdPath -SizeBytes (${DiskSizeGB}GB) -Dynamic | Out-Null
        }
    }

    # Create the VM
    Write-Host "Creating VM '$vmName' (Generation $Generation)"
    # If VHD is to be connected later, use -NoVHD to allow custom attach; but New-VM supports -VHDPath too.
    New-VM -Name $vmName -MemoryStartupBytes (${MemoryStartupMB}MB) -Generation $Generation -Path $vmDir -BootDevice VHD -ErrorAction Stop | Out-Null

    # Remove default VHD drive and attach our VHD (guard vs duplicates)
    $existingHardDrives = Get-VMHardDiskDrive -VMName $vmName -ErrorAction SilentlyContinue
    foreach ($hd in $existingHardDrives) {
        try {
            Remove-VMHardDiskDrive -VMName $vmName -ControllerType $hd.ControllerType -ControllerNumber $hd.ControllerNumber -ControllerLocation $hd.ControllerLocation -Confirm:$false -ErrorAction SilentlyContinue
        } catch { }
    }
    Add-VMHardDiskDrive -VMName $vmName -Path $vhdPath

    # CPU and memory settings
    Set-VMProcessor -VMName $vmName -Count $ProcessorCount
    Set-VMMemory -VMName $vmName -StartupBytes (${MemoryStartupMB}MB) -DynamicMemoryEnabled $false

    # Connect network
    Connect-VMNetworkAdapter -VMName $vmName -SwitchName $SwitchName

    # Enable checkpoints by default
    Set-VM -Name $vmName -CheckpointType Production

    Write-Host "Starting VM $vmName ..."
    Start-VM -Name $vmName

    # If AdminPassword was provided and the VM supports PowerShell Direct, set local Administrator password
    if (-not [string]::IsNullOrWhiteSpace($AdminPassword)) {
        Write-Host "Attempting to set Administrator password inside VM via PowerShell Direct (only works for Windows guests with PSDirect enabled)..."
        try {
            $secPass = ConvertTo-SecureString -String $AdminPassword -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential("Administrator", $secPass)
            # Wait for VM to boot enough for PowerShell Direct to accept connections (this may require adjustments)
            Start-Sleep -Seconds 20
            Invoke-Command -VMName $vmName -Credential $cred -ScriptBlock {
                param($pwd)
                net user Administrator $pwd
            } -ArgumentList $AdminPassword -ErrorAction Stop
            Write-Host "Administrator password set via PowerShell Direct."
        } catch {
            Write-Warning "Could not set Administrator password via PowerShell Direct. VM may not be ready or not a Windows guest supporting PSDirect. Error: $_"
        }
    }

    Write-Host "VM $vmName created and started. VHD path: $vhdPath"
}

Write-Host "All done. Created $VMCount VM(s) with prefix '$VMNamePrefix'."
