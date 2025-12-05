<#
.SYNOPSIS
  Copy files into a Windows VM on the same Hyper-V host using PowerShell Direct.

.DESCRIPTION
  Uses New-PSSession -VMName (PowerShell Direct) and Copy-Item -ToSession to transfer files.
  This requires:
  - The VM is a Windows guest (Windows 10/Server 2016+) running on the same host.
  - You know credentials for a local account (e.g., Administrator) inside the guest.
  - Hyper-V and PowerShell session support present on host.
  - The VM must be running.

.PARAMETER VMName
  Name of the VM (as seen by Hyper-V).

.PARAMETER SourcePath
  Path on the host to file or folder to copy. Supports wildcard and directories (use -Recurse).

.PARAMETER DestinationPath
  Destination path inside the VM (e.g., C:\Users\Administrator\Desktop). If it doesn't exist it will be created.

.PARAMETER Credential
  PSCredential for a local user in the guest (if omitted you will be prompted).

.EXAMPLE
  .\copy-vm-files-psdirect.ps1 -VMName "winvm-1" -SourcePath "C:\Files\MyApp" -DestinationPath "C:\Temp\MyApp"

#>

param(
    [Parameter(Mandatory=$true)][string]$VMName,
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [Parameter(Mandatory=$true)][string]$DestinationPath,
    [System.Management.Automation.PSCredential]$Credential
)

function Ensure-HyperV {
    if (-not (Get-Module -ListAvailable -Name Hyper-V)) {
        Write-Error "Hyper-V PowerShell module not found. Please run on a Hyper-V host with the Hyper-V module installed."
        exit 1
    }
}

Ensure-HyperV

# Validate VM exists and is running
$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) {
    Write-Error "VM '$VMName' not found."
    exit 2
}
if ($vm.State -ne 'Running') {
    Write-Error "VM '$VMName' is not running. Start the VM and retry."
    exit 3
}

# Prompt for credentials if not supplied
if (-not $Credential) {
    $Credential = Get-Credential -Message "Enter credentials for an account in the guest OS (e.g. Administrator)"
}

# Create PSDirect session to the VM
try {
    Write-Host "Creating PowerShell Direct session to VM '$VMName'..."
    $sess = New-PSSession -VMName $VMName -Credential $Credential -ErrorAction Stop
} catch {
    Write-Error "Failed to create PSDirect session to VM. Ensure VM is running, supports PowerShell Direct, and credentials are correct. Error: $_"
    exit 4
}

try {
    # Ensure destination path exists inside VM
    Write-Host "Ensuring destination path '$DestinationPath' exists inside VM..."
    Invoke-Command -Session $sess -ScriptBlock {
        param($dest)
        if (-not (Test-Path -Path $dest)) {
            New-Item -Path $dest -ItemType Directory -Force | Out-Null
        }
    } -ArgumentList $DestinationPath -ErrorAction Stop

    # Copy items (supports folders via -Recurse)
    Write-Host "Copying $SourcePath -> $VMName:$DestinationPath ..."
    Copy-Item -ToSession $sess -Path $SourcePath -Destination $DestinationPath -Recurse -Force -ErrorAction Stop

    Write-Host "Copy completed successfully."
} catch {
    Write-Error "Copy failed: $_"
} finally {
    if ($sess) { Remove-PSSession $sess }
}
