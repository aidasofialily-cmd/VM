<#
.SYNOPSIS
  Uninstaller helper for VM Tooltip Tray.

.DESCRIPTION
  Removes the installed files, Scheduled Task (system install) or HKCU Run key (per-user install), and Start Menu shortcuts.

.PARAMETER InstallPath
  Path where the script was installed. If omitted, defaults are used based on -System flag.

.PARAMETER System
  If specified, perform system uninstall actions (Program Files + Scheduled Task). Requires Admin.

.PARAMETER TaskName
  Name of the Scheduled Task to remove (default "VMTooltipTray").

#>

param(
    [string]$InstallPath = "",
    [switch]$System,
    [string]$TaskName = "VMTooltipTray"
)

if ($System) {
    if (-not ([bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).Groups -match "S-1-5-32-544"))) {
        Write-Error "System uninstall requires Administrator. Re-run this script elevated."
        exit 1
    }
    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        $InstallPath = Join-Path $env:ProgramFiles "VMTooltipTray"
    }
} else {
    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        $InstallPath = Join-Path $env:LOCALAPPDATA "VMTooltipTray"
    }
}

# Remove Scheduled Task if system
if ($System) {
    try {
        if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
            Write-Host "Removed Scheduled Task: $TaskName"
        } else {
            Write-Host "Scheduled Task $TaskName not found."
        }
    } catch {
        Write-Warning "Failed to remove Scheduled Task: $($_.Exception.Message)"
    }
} else {
    # Remove HKCU Run entry
    try {
        Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "VMTooltipTray" -ErrorAction SilentlyContinue
        Write-Host "Removed HKCU Run entry (if present)."
    } catch {
        Write-Warning "Failed to remove HKCU Run entry: $($_.Exception.Message)"
    }
}

# Remove Start Menu shortcut(s)
try {
    $startMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\VMTooltipTray"
    if (Test-Path $startMenu) {
        Remove-Item -Path $startMenu -Recurse -Force -ErrorAction Stop
        Write-Host "Removed Start Menu shortcuts."
    }
} catch {
    Write-Warning "Failed to remove Start Menu shortcuts: $($_.Exception.Message)"
}

# Remove installed files
try {
    if (Test-Path $InstallPath) {
        Remove-Item -Path $InstallPath -Recurse -Force -ErrorAction Stop
        Write-Host "Removed installed files at $InstallPath"
    } else {
        Write-Host "Install path $InstallPath not found."
    }
} catch {
    Write-Warning "Failed to remove installed files: $($_.Exception.Message)"
}

Write-Host "Uninstall complete. If the tray app is still running, please close it manually (right-click -> Exit) or log off the user session."
