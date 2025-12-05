<#
.SYNOPSIS
  Create a VHDX on the host, format it, copy files into it, and attach it to a VM.

.DESCRIPTION
  This approach works for Windows and Linux guests because the VM simply receives
  a new disk. Copy files on the host into the VHDX before attaching; the VM can then mount/use them.

  Requires:
  - Run as Administrator on the Hyper-V host.
  - VM can be running or off (attaching hot-add depends on guest support).

.PARAMETER VMName
  Target VM name.

.PARAMETER SourcePath
  Local host path (file or directory) to copy into the VHDX.

.PARAMETER VhdxPath
  Full path for the new VHDX file (e.g., C:\HyperV\Disks\vm-data.vhdx).

.PARAMETER VhdxSizeGB
  Size of the VHDX to create (GB). Must be large enough to hold SourcePath contents.

.PARAMETER DriveLetter
  When mounting on the host to populate content, the chosen drive letter (optional). If omitted an available drive letter will be assigned.

.EXAMPLE
  .\create-and-attach-vhdx-with-files.ps1 -VMName "vm1" -SourcePath "C:\Files\MyData" -VhdxPath "C:\HyperV\VMs\vm1-data.vhdx" -VhdxSizeGB 20

#>

param(
    [Parameter(Mandatory=$true)][string]$VMName,
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [Parameter(Mandatory=$true)][string]$VhdxPath,
    [int]$VhdxSizeGB = 20,
    [string]$DriveLetter
)

function Ensure-Admin {
    $isAdmin = ([bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).Groups -match "S-1-5-32-544"))
    if (-not $isAdmin) {
        Write-Error "This script must be run as Administrator."
        exit 1
    }
}

Ensure-Admin

# Validate inputs
if (-not (Test-Path $SourcePath)) {
    Write-Error "SourcePath '$SourcePath' does not exist."
    exit 2
}

$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) {
    Write-Error "VM '$VMName' not found."
    exit 3
}

$vhdDir = Split-Path -Path $VhdxPath -Parent
if (-not (Test-Path $vhdDir)) { New-Item -ItemType Directory -Path $vhdDir -Force | Out-Null }

# Create VHDX
Write-Host "Creating VHDX at $VhdxPath ($VhdxSizeGB GB)..."
New-VHD -Path $VhdxPath -SizeBytes (${VhdxSizeGB}GB) -Dynamic -ErrorAction Stop | Out-Null

# Mount the VHD and prepare filesystem
Write-Host "Mounting VHDX..."
$mounted = Mount-VHD -Path $VhdxPath -PassThru -ErrorAction Stop

# Get associated disk number
Start-Sleep -Seconds 1
$disk = Get-Disk | Where-Object { $_.Location -like "*$($mounted.Path)*" -or ($_.FriendlyName -match [IO.Path]::GetFileNameWithoutExtension($VhdxPath)) } | Sort-Object Number | Select-Object -First 1
if (-not $disk) {
    # As fallback find the largest Raw disk that is offline
    $disk = Get-Disk | Where-Object PartitionStyle -eq 'RAW' | Sort-Object Number | Select-Object -First 1
}
if (-not $disk) {
    Dismount-VHD -Path $VhdxPath -ErrorAction SilentlyContinue
    Write-Error "Could not find mounted disk for the VHDX."
    exit 4
}

$diskNumber = $disk.Number
Write-Host "Initializing disk #$diskNumber..."
try {
    Initialize-Disk -Number $diskNumber -PartitionStyle MBR -ErrorAction Stop
} catch {
    # ignore if already initialized
}

$partition = New-Partition -DiskNumber $diskNumber -UseMaximumSize -AssignDriveLetter -ErrorAction Stop
$drive = ($partition | Get-Volume).DriveLetter + ":"
if ($DriveLetter) {
    # Attempt to change to requested letter
    try {
        Set-Partition -DriveLetter ((Get-Volume -Partition $partition).DriveLetter) -NewDriveLetter $DriveLetter -ErrorAction Stop
        $drive = "$DriveLetter`:"
    } catch {
        Write-Warning "Could not set drive letter to $DriveLetter; using $drive instead."
    }
}

Write-Host "Formatting volume $drive ..."
Format-Volume -DriveLetter $drive.TrimEnd(':') -FileSystem NTFS -NewFileSystemLabel "vm-data" -Confirm:$false -ErrorAction Stop | Out-Null

# Copy files into mounted VHDX
Write-Host "Copying files into $drive ..."
# Use Robocopy for robust copy if it's a directory
if ((Get-Item $SourcePath).PSIsContainer) {
    $src = (Resolve-Path $SourcePath).Path
    robocopy.exe $src $drive /MIR /COPY:DAT /R:2 /W:2 | Out-Null
} else {
    Copy-Item -Path $SourcePath -Destination $drive -Force -ErrorAction Stop
}

# Dismount and attach to VM
Write-Host "Dismounting VHDX..."
Dismount-VHD -Path $VhdxPath -ErrorAction Stop

Write-Host "Attaching VHDX to VM '$VMName'..."
# If VM is running and supports hot-add, Add-VMHardDiskDrive will attach online.
Add-VMHardDiskDrive -VMName $VMName -Path $VhdxPath -ErrorAction Stop

Write-Host "VHDX created, populated and attached to VM '$VMName': $VhdxPath"
