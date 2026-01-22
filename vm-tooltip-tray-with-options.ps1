<#
.SYNOPSIS
  Hyper-V tray utility with per-VM options (start/stop/restart/save/pause/connect) and run-at-logon helper.

.DESCRIPTION
  Enhanced version of vm-tooltip-tray.ps1 that:
  - Shows a compact summary tooltip in the system tray.
  - Left-click shows a balloon with per-VM details.
  - Right-click context menu includes:
      * Refresh
      * VMs -> per-VM submenu with Start / Stop / Restart / Save / Pause / Connect
      * Open Hyper-V Manager
      * Install/Uninstall Run at Logon (adds/removes a Run registry entry for the current user)
      * Exit
  - Supports filtering which VMs are shown via wildcard (parameter -VMNameFilter).
  - Optionally installs itself to run at current user's logon (-InstallRunAtLogon) or removes that entry (-UninstallRunAtLogon).
  - Requires Hyper-V PowerShell module (Get-VM, Get-VMNetworkAdapter). VM control actions require sufficient privileges (Administrator recommended).

.PARAMETER RefreshIntervalSeconds
  Polling interval in seconds (default 30).

.PARAMETER VMNameFilter
  Wildcard filter for VM names (default "*").

.PARAMETER InstallRunAtLogon
  If specified, add a Run registry entry for the current user to start this script at logon.

.PARAMETER UninstallRunAtLogon
  If specified, remove the Run registry entry (if present).

.EXAMPLE
  # Start tray utility for all VMs
  powershell -ExecutionPolicy Bypass -File .\vm-tooltip-tray-with-options.ps1

  # Start tray utility for VMs matching "web*"
  powershell -ExecutionPolicy Bypass -File .\vm-tooltip-tray-with-options.ps1 -VMNameFilter "web*"

  # Install run-at-logon for current user (creates HKCU Run entry)
  powershell -ExecutionPolicy Bypass -File .\vm-tooltip-tray-with-options.ps1 -InstallRunAtLogon

.NOTES
  - Run interactively; the tray icon belongs to the launching user session.
  - To control VMs (start/stop/etc.) the user typically needs Administrator privileges or Hyper-V permissions.
  - Connect uses vmconnect.exe localhost "VMName"; vmconnect should be present on the system (Hyper-V feature/tools).
#>

param(
    [int]$RefreshIntervalSeconds = 30,
    [string]$VMNameFilter = "*",
    [switch]$InstallRunAtLogon,
    [switch]$UninstallRunAtLogon
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Is-Admin {
    return ([bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).Groups -match "S-1-5-32-544"))
}

function Show-InfoBox([string]$text, [string]$title="VM Tooltip") {
    [System.Windows.Forms.MessageBox]::Show($text, $title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}

function Show-ErrorBox([string]$text, [string]$title="VM Tooltip") {
    [System.Windows.Forms.MessageBox]::Show($text, $title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
}

function Get-VMInfo {
    try {
        $vms = Get-VM -ErrorAction Stop | Where-Object { $_.Name -like $VMNameFilter }
    } catch {
        return @{ Error = "Get-VM failed: $($_.Exception.Message)"; VMs = @() }
    }

    $list = @()
    foreach ($vm in $vms) {
        $name = $vm.Name
        $state = $vm.State.ToString()
        $assignedMemoryMB = $null
        $processorCount = $null
        try {
            $assignedMemoryMB = if ($vm.MemoryAssigned) { [int]($vm.MemoryAssigned / 1MB) } else { $vm.MemoryStartup }
            $processorCount = if ($vm.ProcessorCount) { $vm.ProcessorCount } else { $null }
        } catch { }

        # IPs: attempt to read published IP addresses (requires integration services / guest services)
        $ips = @()
        try {
            $adapters = Get-VMNetworkAdapter -VMName $name -ErrorAction SilentlyContinue
            if ($adapters) {
                foreach ($a in $adapters) {
                    if ($a.IPAddresses) {
                        $ips += $a.IPAddresses
                    }
                }
            }
        } catch { }

        $ips = $ips | Where-Object { $_ -and ($_ -ne "0.0.0.0") } | Select-Object -Unique

        $list += [PSCustomObject]@{
            Name = $name
            State = $state
            MemoryMB = $assignedMemoryMB
            CPUs = $processorCount
            IPs = if ($ips) { $ips } else { @() }
        }
    }

    return @{ VMs = $list }
}

function Build-SummaryText {
    param($vmInfo)
    if ($vmInfo.Error) { return $vmInfo.Error }
    $list = $vmInfo.VMs
    $running = ($list | Where-Object { $_.State -eq 'Running' }).Count
    $other = $list.Count - $running
    return "$running running / $other other"
}

function Build-BalloonText {
    param($vmInfo, $maxLines = 12)
    if ($vmInfo.Error) { return $vmInfo.Error }
    $lines = @()
    foreach ($vm in $vmInfo.VMs) {
        $ipText = if ($vm.IPs.Count -gt 0) { ($vm.IPs -join ", ") } else { "no IP" }
        $mem = if ($vm.MemoryMB) { "$($vm.MemoryMB)MB" } else { "N/A" }
        $cpu = if ($vm.CPUs) { $vm.CPUs } else { "N/A" }
        $lines += "$($vm.Name): $($vm.State) | CPU:$cpu RAM:$mem | $ipText"
    }

    if ($lines.Count -eq 0) { return "No VMs found (filter: $VMNameFilter)." }

    if ($lines.Count -gt $maxLines) {
        $trim = $lines[0..($maxLines-2)]
        $trim += "... and $($lines.Count - ($maxLines-1)) more"
        $lines = $trim
    }

    return ($lines -join [Environment]::NewLine)
}

function Take-VMScreenshot([string]$VMName) {
    try {
        if (-not (Is-Admin)) {
            Show-ErrorBox "Taking screenshots requires Administrator privileges."
            return
        }

        # Ensure screens directory exists
        $screenDir = Join-Path (Split-Path $MyInvocation.MyCommand.Path) "screens"
        if (-not (Test-Path $screenDir)) { New-Item -ItemType Directory -Path $screenDir | Out-Null }

        # Use CIM to get the thumbnail image (GIF format)
        $vm = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem -Filter "ElementName='$VMName'" -ErrorAction Stop
        $mgmt = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_VirtualSystemManagementService -ErrorAction Stop

        $result = Invoke-CimMethod -InputObject $mgmt -MethodName GetVirtualSystemThumbnailImage -Arguments @{
            TargetSystem = $vm.CimInstancePath
            WidthPixels = 1024
            HeightPixels = 768
        }

        if ($result.ReturnValue -eq 0 -and $result.ImageData) {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $fileName = "$($VMName)_$($timestamp).gif"
            $filePath = Join-Path $screenDir $fileName
            [System.IO.File]::WriteAllBytes($filePath, $result.ImageData)
            Show-InfoBox "Screenshot saved to $filePath"
        } else {
            Show-ErrorBox "Failed to capture screenshot. Ensure the VM is running or has been started at least once."
        }
    } catch {
        Show-ErrorBox "Screenshot failed for $VMName: $($_.Exception.Message)"
    }
}

function Show-VMDashboard {
    $dashForm = New-Object System.Windows.Forms.Form
    $dashForm.Text = "VM Dashboard - Screens"
    $dashForm.Size = New-Object System.Drawing.Size(600, 450)
    $dashForm.StartPosition = "CenterScreen"

    $flow = New-Object System.Windows.Forms.FlowLayoutPanel
    $flow.Dock = "Fill"
    $flow.AutoScroll = $true
    $dashForm.Controls.Add($flow)

    $updateUI = {
        $flow.Controls.Clear()
        $global:latestInfo = Get-VMInfo
        $vmlist = $global:latestInfo.VMs

        foreach ($vm in $vmlist) {
            $vName = $vm.Name
            $vState = $vm.State

            $panel = New-Object System.Windows.Forms.GroupBox
            $panel.Text = $vName
            $panel.Size = New-Object System.Drawing.Size(560, 90)

            $lblStatus = New-Object System.Windows.Forms.Label
            $lblStatus.Text = "Status: $vState"
            $lblStatus.Location = New-Object System.Drawing.Point(10, 25)
            $lblStatus.AutoSize = $true
            $panel.Controls.Add($lblStatus)

            $btnStart = New-Object System.Windows.Forms.Button
            $btnStart.Text = "Start"
            $btnStart.Location = New-Object System.Drawing.Point(10, 50)
            $btnStart.add_Click({ Perform-VMAction -Action "Start" -VMName $vName; &$updateUI }.GetNewClosure())
            $panel.Controls.Add($btnStart)

            $btnStop = New-Object System.Windows.Forms.Button
            $btnStop.Text = "Stop"
            $btnStop.Location = New-Object System.Drawing.Point(90, 50)
            $btnStop.add_Click({ Perform-VMAction -Action "Stop" -VMName $vName; &$updateUI }.GetNewClosure())
            $panel.Controls.Add($btnStop)

            $btnSnap = New-Object System.Windows.Forms.Button
            $btnSnap.Text = "Screenshot"
            $btnSnap.Location = New-Object System.Drawing.Point(170, 50)
            $btnSnap.add_Click({ Take-VMScreenshot -VMName $vName }.GetNewClosure())
            $panel.Controls.Add($btnSnap)

            $btnConnect = New-Object System.Windows.Forms.Button
            $btnConnect.Text = "Connect"
            $btnConnect.Location = New-Object System.Drawing.Point(250, 50)
            $btnConnect.add_Click({ Perform-VMAction -Action "Connect" -VMName $vName }.GetNewClosure())
            $panel.Controls.Add($btnConnect)

            $flow.Controls.Add($panel)
        }
    }

    &$updateUI
    $dashForm.ShowDialog() | Out-Null
}

function Perform-VMAction {
    param(
        [Parameter(Mandatory=$true)][ValidateSet("Start","Stop","Restart","Save","Pause","Resume","Connect")][string]$Action,
        [Parameter(Mandatory=$true)][string]$VMName
    )

    # Actions that require admin/privileges
    if (-not (Is-Admin)) {
        Show-ErrorBox "VM control actions require Administrator privileges. Restart PowerShell as Administrator and re-run the tray utility to use Start/Stop/etc."
        return
    }

    try {
        switch ($Action) {
            "Start" {
                Start-VM -Name $VMName -ErrorAction Stop
                Show-InfoBox "Start command issued to '$VMName'."
            }
            "Stop" {
                $res = [System.Windows.Forms.MessageBox]::Show("Stop VM '$VMName'? This performs a graceful shutdown if supported; choose 'No' to force-turn-off.", "Confirm Stop", [System.Windows.Forms.MessageBoxButtons]::YesNoCancel, [System.Windows.Forms.MessageBoxIcon]::Question)
                if ($res -eq [System.Windows.Forms.DialogResult]::Yes) {
                    Stop-VM -Name $VMName -Force -ErrorAction Stop
                    Show-InfoBox "Stop (force) issued to '$VMName'."
                } elseif ($res -eq [System.Windows.Forms.DialogResult]::No) {
                    # Attempt graceful shutdown via Guest Shutdown first
                    try {
                        Stop-VM -Name $VMName -Shutdown -ErrorAction Stop
                        Show-InfoBox "Shutdown request sent to '$VMName'."
                    } catch {
                        Stop-VM -Name $VMName -Force -ErrorAction Stop
                        Show-InfoBox "Shutdown failed; forced stop issued to '$VMName'."
                    }
                }
            }
            "Restart" {
                $res = [System.Windows.Forms.MessageBox]::Show("Restart VM '$VMName' now?", "Confirm Restart", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
                if ($res -eq [System.Windows.Forms.DialogResult]::Yes) {
                    Restart-VM -Name $VMName -Force -ErrorAction Stop
                    Show-InfoBox "Restart (force) issued to '$VMName'."
                }
            }
            "Save" {
                $res = [System.Windows.Forms.MessageBox]::Show("Save VM '$VMName' state? (This creates a saved state you can later resume)", "Confirm Save", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
                if ($res -eq [System.Windows.Forms.DialogResult]::Yes) {
                    Save-VM -Name $VMName -ErrorAction Stop
                    Show-InfoBox "Save issued to '$VMName'."
                }
            }
            "Pause" {
                Suspend-VM -Name $VMName -ErrorAction Stop
                Show-InfoBox "Pause (suspend) issued to '$VMName'."
            }
            "Resume" {
                Resume-VM -Name $VMName -ErrorAction Stop
                Show-InfoBox "Resume issued to '$VMName'."
            }
            "Connect" {
                # Launch VMConnect for localhost
                $vmconnect = "vmconnect.exe"
                Start-Process -FilePath $vmconnect -ArgumentList "localhost","$VMName" -ErrorAction Stop
            }
        }
    } catch {
        Show-ErrorBox "Action $Action on $VMName failed: $($_.Exception.Message)"
    } finally {
        # Refresh view after action
        try {
            $global:latestInfo = Get-VMInfo
            $notify.Text = Build-SummaryText $global:latestInfo
            Rebuild-VMMenu
        } catch { }
    }
}

function Add-RunAtLogon {
    param([string]$EntryName = "VMTooltipTray")
    try {
        $scriptPath = $MyInvocation.MyCommand.Path
        if (-not $scriptPath) { throw "Could not determine script path; run from a file path." }
        $cmd = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name $EntryName -Value $cmd -ErrorAction Stop
        Show-InfoBox "Run-at-logon entry created for current user ($EntryName)."
    } catch {
        Show-ErrorBox "Failed to add Run-at-logon entry: $($_.Exception.Message)"
    }
}

function Remove-RunAtLogon {
    param([string]$EntryName = "VMTooltipTray")
    try {
        Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name $EntryName -ErrorAction Stop
        Show-InfoBox "Run-at-logon entry removed ($EntryName)."
    } catch {
        Show-ErrorBox "Failed to remove Run-at-logon entry: $($_.Exception.Message)"
    }
}

# Create NotifyIcon
$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = [System.Drawing.SystemIcons]::Application
$notify.Visible = $true
$notify.Text = "Hyper-V VMs"

# Context menu and items
$menu = New-Object System.Windows.Forms.ContextMenuStrip

$miRefresh = New-Object System.Windows.Forms.ToolStripMenuItem "Refresh"
$miDashboard = New-Object System.Windows.Forms.ToolStripMenuItem "Show VM Dashboard (Screens)"
$miVMs = New-Object System.Windows.Forms.ToolStripMenuItem "VMs"
$miScreens = New-Object System.Windows.Forms.ToolStripMenuItem "Open Screens Folder"
$miOpen = New-Object System.Windows.Forms.ToolStripMenuItem "Open Hyper-V Manager"
$miInstallRun = New-Object System.Windows.Forms.ToolStripMenuItem "Install Run at Logon"
$miUninstallRun = New-Object System.Windows.Forms.ToolStripMenuItem "Uninstall Run at Logon"
$miExit = New-Object System.Windows.Forms.ToolStripMenuItem "Exit"

$menu.Items.Add($miRefresh) | Out-Null
$menu.Items.Add($miDashboard) | Out-Null
$menu.Items.Add($miVMs) | Out-Null
$menu.Items.Add($miScreens) | Out-Null
$menu.Items.Add($miOpen) | Out-Null
$menu.Items.Add("-") | Out-Null
$menu.Items.Add($miInstallRun) | Out-Null
$menu.Items.Add($miUninstallRun) | Out-Null
$menu.Items.Add("-") | Out-Null
$menu.Items.Add($miExit) | Out-Null

$notify.ContextMenuStrip = $menu

# Event handlers
$miRefresh.add_Click({
    try {
        $global:latestInfo = Get-VMInfo
        $notify.Text = Build-SummaryText $global:latestInfo
        Rebuild-VMMenu
    } catch { }
})

$miDashboard.add_Click({
    Show-VMDashboard
})

$miScreens.add_Click({
    $screenDir = Join-Path (Split-Path $MyInvocation.MyCommand.Path) "screens"
    if (-not (Test-Path $screenDir)) { New-Item -ItemType Directory -Path $screenDir | Out-Null }
    Start-Process "explorer.exe" -ArgumentList "`"$screenDir`""
})

$miOpen.add_Click({
    try {
        Start-Process "virtmgmt.msc" -ErrorAction SilentlyContinue
    } catch {
        try { Start-Process "mmc.exe" -ArgumentList "virtmgmt.msc" -ErrorAction SilentlyContinue } catch { }
    }
})

$miInstallRun.add_Click({
    Add-RunAtLogon
})

$miUninstallRun.add_Click({
    Remove-RunAtLogon
})

$miExit.add_Click({
    $notify.Visible = $false
    $notify.Dispose()
    if ($timer) { $timer.Stop(); $timer.Dispose() }
    if ($form) { $form.Close() }
})

# Build VM menu (rebuilds when refreshed)
function Rebuild-VMMenu {
    # Clear existing items
    $miVMs.DropDownItems.Clear()

    if ($global:latestInfo -and $global:latestInfo.Error) {
        $miVMs.DropDownItems.Add("Error: $($global:latestInfo.Error)") | Out-Null
        return
    }

    $vmlist = @()
    if ($global:latestInfo) { $vmlist = $global:latestInfo.VMs } else { $vmlist = Get-VMInfo.VMs }

    if ($vmlist.Count -eq 0) {
        $miVMs.DropDownItems.Add("No VMs found (filter: $VMNameFilter)") | Out-Null
        return
    }

    foreach ($vm in $vmlist) {
        $vmName = $vm.Name
        $vmItem = New-Object System.Windows.Forms.ToolStripMenuItem $vmName

        # Action items
        $miStart = New-Object System.Windows.Forms.ToolStripMenuItem "Start"
        $miStop = New-Object System.Windows.Forms.ToolStripMenuItem "Stop"
        $miRestart = New-Object System.Windows.Forms.ToolStripMenuItem "Restart"
        $miSave = New-Object System.Windows.Forms.ToolStripMenuItem "Save"
        $miPause = New-Object System.Windows.Forms.ToolStripMenuItem "Pause"
        $miResume = New-Object System.Windows.Forms.ToolStripMenuItem "Resume"
        $miScreenshot = New-Object System.Windows.Forms.ToolStripMenuItem "Take Screenshot"
        $miConnect = New-Object System.Windows.Forms.ToolStripMenuItem "Connect"

        # Hook up event handlers capturing $vmName correctly using GetNewClosure
        $miStart.add_Click({ Perform-VMAction -Action "Start" -VMName $vmName }.GetNewClosure())
        $miStop.add_Click({ Perform-VMAction -Action "Stop" -VMName $vmName }.GetNewClosure())
        $miRestart.add_Click({ Perform-VMAction -Action "Restart" -VMName $vmName }.GetNewClosure())
        $miSave.add_Click({ Perform-VMAction -Action "Save" -VMName $vmName }.GetNewClosure())
        $miPause.add_Click({ Perform-VMAction -Action "Pause" -VMName $vmName }.GetNewClosure())
        $miResume.add_Click({ Perform-VMAction -Action "Resume" -VMName $vmName }.GetNewClosure())
        $miScreenshot.add_Click({ Take-VMScreenshot -VMName $vmName }.GetNewClosure())
        $miConnect.add_Click({ Perform-VMAction -Action "Connect" -VMName $vmName }.GetNewClosure())

        # Add items to vmItem
        $vmItem.DropDownItems.Add($miStart) | Out-Null
        $vmItem.DropDownItems.Add($miStop) | Out-Null
        $vmItem.DropDownItems.Add($miRestart) | Out-Null
        $vmItem.DropDownItems.Add($miSave) | Out-Null
        $vmItem.DropDownItems.Add($miPause) | Out-Null
        $vmItem.DropDownItems.Add($miResume) | Out-Null
        $vmItem.DropDownItems.Add("-") | Out-Null
        $vmItem.DropDownItems.Add($miScreenshot) | Out-Null
        $vmItem.DropDownItems.Add($miConnect) | Out-Null

        $miVMs.DropDownItems.Add($vmItem) | Out-Null
    }
}

# Left-click shows balloon
$notify.add_MouseClick({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $text = Build-BalloonText $global:latestInfo 12
        try {
            $notify.BalloonTipTitle = "Hyper-V VM details"
            $notify.BalloonTipText = $text
            $notify.ShowBalloonTip(5000)
        } catch {
            $notify.Text = $text.Substring(0, [Math]::Min(63, $text.Length))
        }
    }
})

# MouseMove updates tooltip summary text
$notify.add_MouseMove({
    try {
        $notify.Text = Build-SummaryText $global:latestInfo
    } catch { }
})

# Hidden form for message loop
$form = New-Object System.Windows.Forms.Form
$form.ShowInTaskbar = $false
$form.WindowState = 'Minimized'
$form.Load.Add({ $form.Hide() })

# Initial poll and menu build
$global:latestInfo = Get-VMInfo
$notify.Text = Build-SummaryText $global:latestInfo
Rebuild-VMMenu

# Handle Install/Uninstall parameters early
if ($InstallRunAtLogon) {
    Add-RunAtLogon
}
if ($UninstallRunAtLogon) {
    Remove-RunAtLogon
}

# Timer to refresh info
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $RefreshIntervalSeconds * 1000
$timer.Add_Tick({
    try {
        $global:latestInfo = Get-VMInfo
        $notify.Text = Build-SummaryText $global:latestInfo
        Rebuild-VMMenu
    } catch { }
})
$timer.Start()

$form.Add_FormClosing({
    param($s, $args)
    $timer.Stop()
    $notify.Visible = $false
    $notify.Dispose()
    $timer.Dispose()
})

[System.Windows.Forms.Application]::Run($form)
