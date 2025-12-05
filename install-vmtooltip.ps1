<#
.SYNOPSIS
  Installer helper for VM Tooltip Tray.

.DESCRIPTION
  Copies the tray script to a target folder and configures auto-start:
    - Per-user (default): copy to %LocalAppData%\VMTooltipTray and add HKCU Run key.
    - System (-System): copy to "C:\Program Files\VMTooltipTray" and register a Scheduled Task that runs at user logon with RunLevel Highest.

  Usage examples:
    # Per-user install (no admin required)
    .\install-vmtooltip.ps1 -ScriptSource .\vm-tooltip-tray-with-options.ps1

    # System install (requires Admin)
    Start-Process powershell -Verb runAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `".\install-vmtooltip.ps1`" -ScriptSource .\vm-tooltip-tray-with-options.ps1 -System"

.PARAMETER ScriptSource
  Path to the tray script file to install.

.PARAMETER InstallPath
  Optional: custom install path. If omitted, defaults:
    - Per-user: $env:LOCALAPPDATA\VMTooltipTray
    - System: $env:ProgramFiles\VMTooltipTray

.PARAMETER System
  If specified, perform a system install to Program Files and register a Scheduled Task (requires Admin).

.PARAMETER TaskName
  Name of the Scheduled Task (default "VMTooltipTray").

#>

param(
    [Parameter(Mandatory=$true)][string]$ScriptSource,
    [string]$InstallPath = "",
    [switch]$System,
    [string]$TaskName = "VMTooltipTray"
)

function Ensure-FileExists($path) {
    if (-not (Test-Path $path)) {
        throw "File not found: $path"
    }
}

try {
    Ensure-FileExists $ScriptSource
} catch {
    Write-Error $_.Exception.Message
    exit 1
}

# Resolve full paths
$scriptFull = (Resolve-Path $ScriptSource).Path

if ($System) {
    if (-not ([bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).Groups -match "S-1-5-32-544"))) {
        Write-Error "System install requires Administrator. Re-run this script elevated."
        exit 2
    }
    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        $InstallPath = Join-Path $env:ProgramFiles "VMTooltipTray"
    }
} else {
    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        $InstallPath = Join-Path $env:LOCALAPPDATA "VMTooltipTray"
    }
}

# Create install folder
if (-not (Test-Path $InstallPath)) {
    New-Item -Path $InstallPath -ItemType Directory -Force | Out-Null
    Write-Host "Created folder: $InstallPath"
}

# Copy script
$destScript = Join-Path $InstallPath (Split-Path $scriptFull -Leaf)
Copy-Item -Path $scriptFull -Destination $destScript -Force
Write-Host "Copied script to: $destScript"

# Optionally create helper shortcut in Start Menu (per-user)
try {
    $startMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\VMTooltipTray"
    if (-not (Test-Path $startMenu)) { New-Item -Path $startMenu -ItemType Directory -Force | Out-Null }
    $lnkPath = Join-Path $startMenu "VM Tooltip Tray.lnk"
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($lnkPath)
    $Shortcut.TargetPath = "powershell.exe"
    $Shortcut.Arguments  = "-ExecutionPolicy Bypass -WindowStyle Normal -File `"$destScript`""
    $Shortcut.WorkingDirectory = $InstallPath
    $Shortcut.Save()
    Write-Host "Created Start Menu shortcut: $lnkPath"
} catch {
    Write-Warning "Could not create Start Menu shortcut: $($_.Exception.Message)"
}

if ($System) {
    # Register a Scheduled Task that runs at logon for the current user with highest privileges
    try {
        $username = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$destScript`""
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $principal = New-ScheduledTaskPrincipal -UserId $username -LogonType Interactive -RunLevel Highest
        $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable)
        Register-ScheduledTask -TaskName $TaskName -InputObject $task -Force
        Write-Host "Registered Scheduled Task '$TaskName' for user $username. It will start at user logon."
    } catch {
        Write-Error "Failed to register Scheduled Task. Error: $($_.Exception.Message)"
    }
} else {
    # Create HKCU Run entry for the current user
    try {
        $cmd = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$destScript`""
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "VMTooltipTray" -Value $cmd -Force
        Write-Host "Installed Run-at-logon entry in HKCU for current user."
    } catch {
        Write-Warning "Failed to write HKCU Run entry: $($_.Exception.Message)"
    }
}

Write-Host "Installation complete. Launch the script now or log off/log on to let the auto-start take effect."
