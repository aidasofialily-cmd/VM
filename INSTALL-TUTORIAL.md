```markdown
# VM Tooltip Tray — Installation Tutorial

This tutorial shows how to install and run the Hyper‑V VM Tooltip Tray utility (vm-tooltip-tray-with-options.ps1) on a Windows Hyper‑V host. It covers prerequisites, quick start (per-user), optional system-wide install, run-at-logon options, verification, and uninstall steps.

Contents
- Overview
- Prerequisites
- Files included
- Quick start (per-user, no admin)
- System-wide install (Program Files + Scheduled Task)
- Verifying installation
- Uninstall / cleanup
- Troubleshooting & notes

Overview
The tray utility provides a system tray icon showing a compact Hyper‑V VM summary and a right-click menu to control VMs (Start/Stop/Restart/Save/Pause/Resume/Connect). The utility is a PowerShell script that runs in the interactive user session.

Prerequisites
- Windows with Hyper‑V role or the Hyper‑V PowerShell module installed.
- PowerShell 5.x or later (built in on modern Windows).
- For VM control actions, the launching user should have Hyper‑V permissions (run as Administrator for full control).
- If you plan a system-wide install to Program Files and a Scheduled Task, you will need Administrator privileges.

Files included in this bundle
- vm-tooltip-tray-with-options.ps1 — The tray application script (PowerShell).
- install-vmtooltip.ps1 — Optional installer helper (copies files & configures run-at-logon).
- uninstall-vmtooltip.ps1 — Optional uninstaller helper.
- README / this tutorial.

Quick start — Per-user install (recommended for testing, does not require Admin)
1. Copy the script to a folder in your user profile, e.g.:
   - C:\Users\<you>\AppData\Local\VMTooltipTray\

   Example (PowerShell):
   ```powershell
   $dest = Join-Path $env:LOCALAPPDATA "VMTooltipTray"
   New-Item -ItemType Directory -Path $dest -Force | Out-Null
   Copy-Item -Path .\vm-tooltip-tray-with-options.ps1 -Destination $dest -Force
   ```

2. Run the script in your interactive session:
   ```powershell
   Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$env:LOCALAPPDATA\VMTooltipTray\vm-tooltip-tray-with-options.ps1`"" -WindowStyle Normal
   ```
   Or directly:
   ```powershell
   powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\VMTooltipTray\vm-tooltip-tray-with-options.ps1"
   ```

3. A tray icon will appear in your notification area. Click / right-click to interact.

Optional: install run-at-logon for current user (HKCU Run)
- The script itself can add a Run key when launched with the `-InstallRunAtLogon` parameter. Example:
  ```powershell
  powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\VMTooltipTray\vm-tooltip-tray-with-options.ps1" -InstallRunAtLogon
  ```
- Or use the included installer script with no admin (it will default to per-user install and create an HKCU Run key).

System-wide install (Program Files + Scheduled Task) — requires Admin
Use this if you want the utility installed centrally for the current user to auto-start with elevated run level (Scheduled Task). The installer script supports a `-System` switch.

Example (run PowerShell as Administrator):
```powershell
# From folder containing installer & script:
.\install-vmtooltip.ps1 -ScriptSource .\vm-tooltip-tray-with-options.ps1 -System
```

What this does:
- Copies the script to `C:\Program Files\VMTooltipTray\` (or specified ProgramFiles path).
- Registers a Scheduled Task named `VMTooltipTray` that runs at logon for the launching user with RunLevel Highest. The task uses the current user & interactive logon (no password stored).

Notes about Scheduled Task:
- The task is created with LogonType Interactive, so it will start when the specific user logs on.
- Because it uses RunLevel Highest, the script will run elevated in that user's session (useful if you want control actions without additional prompts). Creating such a task requires admin privileges.

Verifying the installation
- Tray icon: The simplest verification is the visible tray icon and tooltip summary.
- Quick status check in PowerShell:
  ```powershell
  Get-Process -Name powershell -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "*VMTooltipTray*" }
  ```
- Scheduled task (system install):
  ```powershell
  Get-ScheduledTask -TaskName "VMTooltipTray" | Format-List *
  ```
- Run-at-logon registry (per-user HKCU Run):
  ```powershell
  Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "VMTooltipTray" -ErrorAction SilentlyContinue
  ```

Uninstall / cleanup
- If you installed per-user with HKCU Run:
  1. Remove Run key:
     ```powershell
     Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "VMTooltipTray" -ErrorAction SilentlyContinue
     ```
  2. Stop any running instance of the script (close tray icon or kill process).
  3. Delete the install folder:
     ```powershell
     Remove-Item -Path "$env:LOCALAPPDATA\VMTooltipTray" -Recurse -Force
     ```

- If you used the system install (Scheduled Task + Program Files):
  1. From an elevated PowerShell prompt:
     ```powershell
     Unregister-ScheduledTask -TaskName "VMTooltipTray" -Confirm:$false -ErrorAction SilentlyContinue
     Remove-Item -Path "C:\Program Files\VMTooltipTray" -Recurse -Force
     ```
  2. If you used the provided uninstall helper:
     ```powershell
     .\uninstall-vmtooltip.ps1 -System
     ```

Troubleshooting & notes
- No Hyper‑V module / Get-VM errors:
  - Ensure Hyper‑V role/management tools are installed. Run: `Get-Module -ListAvailable Hyper-V` or install via `Install-WindowsFeature -Name Hyper-V -IncludeManagementTools` (Server) or `Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All` (Client).
- Tray icon not visible:
  - Click the up-arrow in the notification area (hidden icons) and pin the icon to the visible area.
  - Focus Assist / Quiet Hours may suppress toast balloons. Disable Focus Assist or allow notifications for the app.
- VM control actions fail (Start/Stop):
  - Run the script as Administrator to ensure the user has permissions to manage Hyper‑V.
  - Some actions require the VM to be in a particular state (e.g., Save on running VM).
- IP addresses not shown:
  - Guest integration services must publish IP addresses. For Linux guests, install the Hyper‑V Linux Integration Services (or use cloud-init and an appropriate agent).
- ExecutionPolicy warnings:
  - Use `-ExecutionPolicy Bypass -File` when launching the script, or set execution policy for the current process: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process`.
- Script path detection:
  - Some features (Run-at-logon helper) rely on the script knowing its path (it uses $MyInvocation.MyCommand.Path). Ensure the script file is not being executed from a one-liner pasted into the console — run it from a saved .ps1 file.

Security considerations
- The tray utility can perform VM control actions. Only install/trust the script on hosts you control.
- HKCU Run key is per-user; Scheduled Task created by the system install runs with elevated RunLevel — protect the device and the user account.
- Be cautious when enabling "AllowEveryone" SMB or other broad permissions if you add file-sharing features.

Next steps & customizations
- Add filtering to only show a subset of VMs (use the `-VMNameFilter` parameter).
- Create a small Windows shortcut or Start Menu entry for the installed script.
- Add logging of user actions (start/stop) for auditing.
- I can provide an MSI-like installer wrapper (using PS2EXE or an actual installer) if you want distribution across multiple machines.

If you'd like, I can:
- Produce an installer that packages the script, creates start menu shortcuts and per-user scheduled tasks, and supports silent install/uninstall.
- Provide a signed executable wrapper to avoid ExecutionPolicy issues.

Tell me which option you prefer and whether you want the system-install helper run now; I can generate the installer commands or runbook for your environment.
```
