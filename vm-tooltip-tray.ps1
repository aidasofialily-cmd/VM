<#
.SYNOPSIS
  System-tray VM tooltip for Hyper-V hosts: shows summary tooltip and detailed balloon with VM info.

.DESCRIPTION
  Runs as a tray icon that periodically polls Hyper-V (Get-VM and Get-VMNetworkAdapter) and:
   - Shows a short tooltip (counts) on hover.
   - Shows a balloon with detailed per-VM info on left-click.
   - Right-click menu: Refresh, Open Hyper-V Manager, Exit.

  Requirements:
   - Windows with Hyper-V role or Hyper-V PowerShell module installed (Get-VM cmdlet).
   - Run in an interactive user session (the tray icon belongs to the user).
   - If you want IP addresses for guests, ensure Integration Services/VMGuest services provide IPs.

.PARAMETER RefreshIntervalSeconds
  Polling interval in seconds (default 30).

.EXAMPLE
  # Launch the tray tooltip utility
  powershell -ExecutionPolicy Bypass -File .\vm-tooltip-tray.ps1

#>

param(
    [int]$RefreshIntervalSeconds = 30
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-VMInfo {
    try {
        $vms = Get-VM -ErrorAction Stop
    } catch {
        return @{ Error = "Get-VM failed: $($_.Exception.Message)" }
    }

    $list = @()
    foreach ($vm in $vms) {
        $name = $vm.Name
        $state = $vm.State.ToString()
        $assignedMemoryMB = $null
        $processorCount = $null
        try {
            # Some properties are directly available on Get-VM; guard against missing
            $assignedMemoryMB = if ($vm.MemoryAssigned) { [int]($vm.MemoryAssigned / 1MB) } else { $null }
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
    $off = ($list | Where-Object { $_.State -ne 'Running' }).Count
    return "$running running / $off other"
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

    if ($lines.Count -eq 0) { return "No VMs found." }

    # Limit lines for balloon readability
    if ($lines.Count -gt $maxLines) {
        $trim = $lines[0..($maxLines-2)]
        $trim += "... and $($lines.Count - ($maxLines-1)) more"
        $lines = $trim
    }

    return ($lines -join [Environment]::NewLine)
}

# Create NotifyIcon
$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = [System.Drawing.SystemIcons]::Application
$notify.Visible = $true
$notify.Text = "Hyper-V VMs"

# Context menu
$menu = New-Object System.Windows.Forms.ContextMenuStrip

$miRefresh = New-Object System.Windows.Forms.ToolStripMenuItem "Refresh"
$miOpen = New-Object System.Windows.Forms.ToolStripMenuItem "Open Hyper-V Manager"
$miExit = New-Object System.Windows.Forms.ToolStripMenuItem "Exit"

$menu.Items.Add($miRefresh) | Out-Null
$menu.Items.Add($miOpen) | Out-Null
$menu.Items.Add("-") | Out-Null
$menu.Items.Add($miExit) | Out-Null

# Hook up click handlers
$miRefresh.add_Click({
    try {
        $global:latestInfo = Get-VMInfo
        $notify.Text = Build-SummaryText $global:latestInfo
    } catch { }
})

$miOpen.add_Click({
    try {
        Start-Process "virtmgmt.msc" -ErrorAction SilentlyContinue
    } catch {
        # fallback to mmc snap-in if needed
        try { Start-Process "mmc.exe" -ArgumentList "virtmgmt.msc" -ErrorAction SilentlyContinue } catch { }
    }
})

$miExit.add_Click({
    # Cleanup and exit application loop
    $notify.Visible = $false
    $notify.Dispose()
    if ($timer) { $timer.Stop(); $timer.Dispose() }
    # Signal to close form
    if ($form) { $form.Close() }
})

# Assign context menu to notify icon (via reflection because NotifyIcon.ContextMenuStrip is strongly typed)
$notify.ContextMenuStrip = $menu

# Left-click shows balloon with details
$notify.add_MouseClick({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $text = Build-BalloonText $global:latestInfo 12
        # Show balloon tip - duration 5000 ms (5s)
        try {
            $notify.BalloonTipTitle = "Hyper-V VM details"
            $notify.BalloonTipText = $text
            $notify.ShowBalloonTip(5000)
        } catch {
            # if balloon fails, fallback to tooltip text
            $notify.Text = $text.Substring(0, [Math]::Min(63, $text.Length))
        }
    }
})

# MouseMove updates tooltip (short summary)
$notify.add_MouseMove({
    try {
        $notify.Text = Build-SummaryText $global:latestInfo
    } catch { }
})

# Hidden form to run message loop so context menu and events work
$form = New-Object System.Windows.Forms.Form
$form.ShowInTaskbar = $false
$form.WindowState = 'Minimized'
$form.Load.Add({ $form.Hide() })

# Initial poll
$global:latestInfo = Get-VMInfo
$notify.Text = Build-SummaryText $global:latestInfo

# Timer to refresh info periodically
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $RefreshIntervalSeconds * 1000
$timer.Add_Tick({
    try {
        $global:latestInfo = Get-VMInfo
        $notify.Text = Build-SummaryText $global:latestInfo
    } catch { }
})
$timer.Start()

# Graceful cleanup on form closing
$form.Add_FormClosing({
    param($s, $args)
    $timer.Stop()
    $notify.Visible = $false
    $notify.Dispose()
    $timer.Dispose()
})

# Run the message loop (this blocks until the user chooses Exit)
[System.Windows.Forms.Application]::Run($form)
