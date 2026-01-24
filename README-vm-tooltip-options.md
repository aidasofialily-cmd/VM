```markdown
# VM Tooltip Tray Utility — with VM options

This is an enhanced Hyper‑V tray utility (PowerShell) that provides a system tray tooltip and per‑VM options so you can manage VMs quickly without opening Hyper‑V Manager.

What it does
- Shows a short tooltip: "X running / Y other".
- Left-click shows a balloon with VM details (state, CPU, RAM, IP).
- Right-click menu includes:
  - Refresh
  - Show VM Dashboard (Screens) -> Opens a GUI window with VM status and control buttons
  - VMs -> per-VM submenu with: Start, Stop, Restart, Save, Pause, Resume, Take Screenshot, Connect
  - Open Screens Folder -> Opens the folder where screenshots are saved
  - Open Hyper‑V Manager
  - Install Run at Logon (adds an HKCU Run entry for the script)
  - Uninstall Run at Logon
  - Exit

Requirements
- Windows with Hyper‑V PowerShell module available (Get-VM, Get-VMNetworkAdapter).
- To issue VM control actions (Start/Stop/Restart/Save/Pause/Resume) the user needs appropriate Hyper‑V permissions — running the script as Administrator is recommended.
- vmconnect.exe must be present for the Connect action (it typically is when Hyper‑V is installed).
- Run the script in an interactive user session (the tray icon appears for the user who launched it).

Usage
- Launch normally:
  powershell -ExecutionPolicy Bypass -File .\vm-tooltip-tray-with-options.ps1

- Filter shown VMs by name (wildcard):
  powershell -ExecutionPolicy Bypass -File .\vm-tooltip-tray-with-options.ps1 -VMNameFilter "web*"

- Change refresh interval (seconds):
  powershell -ExecutionPolicy Bypass -File .\vm-tooltip-tray-with-options.ps1 -RefreshIntervalSeconds 15

- Install run-at-logon (current user):
  powershell -ExecutionPolicy Bypass -File .\vm-tooltip-tray-with-options.ps1 -InstallRunAtLogon

- Uninstall run-at-logon:
  powershell -ExecutionPolicy Bypass -File .\vm-tooltip-tray-with-options.ps1 -UninstallRunAtLogon

Security and notes
- The script will show a friendly error if a VM control action is attempted without Administrator privileges. Re-run as Administrator to allow control actions.
- Stop/Restart/Save actions prompt for confirmation before executing.
- Installing run-at-logon writes a registry Run key under HKCU for the current user. This is convenient for a per-user tray app without requiring elevated scheduled tasks.
- The balloon text and tooltip are subject to Windows' notification size restrictions; long lists may be truncated for readability.

Possible customizations I can add
- Add Start/Stop confirmation options in preferences (disable confirmations).
- Add "Only show VMs in this group/tag" (if you have naming conventions).
- Add logging of actions and status changes.
- Create a Windows Service + per-user agent model so the tray app doesn't need to run in a full user session.
- Use Scheduled Task (with highest privileges) for run-at-logon if you want it system-wide.
- Add actual thumbnail images to the Dashboard (requires periodic background refresh of thumbnails).

If you'd like, I can:
- Add an installer that places the script in Program Files and creates a per-user Run key or scheduled task.
- Add an option to automatically elevate when a VM action is performed (requires manifest / separate executable wrapper).

Tell me which customization you'd like next (installer, auto-elevate, filters, logging), and I'll update the script.
```
```
