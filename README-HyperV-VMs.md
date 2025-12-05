```markdown
# Hyper-V VM Creation script (create-vms.ps1)

This repository contains create-vms.ps1 — a PowerShell script to create Hyper-V virtual machines quickly.

Prerequisites
- Windows 10/11 Pro, Windows Server with Hyper-V role installed.
- Run the script as Administrator.
- Hyper-V PowerShell module available (installed with the Hyper-V role).
- If you plan to use differencing disks, you need a generalized (sysprep'd) Windows VHDX (parent image). For Windows templates, prepare a generalized image with sysprep:
  - Install Windows in a VM.
  - Run `sysprep /generalize /oobe /shutdown` from an elevated prompt.
  - Convert the VM's disk to a VHDX (if needed) and copy it to the host (e.g. C:\Images\WinServ2022_gen.vhdx).
- ExecutionPolicy: you might need to run `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process` before running the script.

Recommended approach (fastest for multiple Windows VMs)
1. Create and sysprep a base Windows VM (as described above).
2. Use `-UseDifferencingDisk -BaseVhdxPath "C:\Images\WinServ2022_gen.vhdx"` to create fast clones.

Network options
- If you want the VMs to have Internet access and be NAT'd behind the host, run the script with `-CreateInternalSwitch` (default in example). This will create an internal switch named `NATSwitch` and configure NAT on 192.168.100.0/24.
- If you already have an external switch (connected to a physical NIC), pass `-SwitchName "YourExternalSwitchName"` and omit `-CreateInternalSwitch`.

Example usages
- Create 1 VM from differencing disk (recommended):
  .\create-vms.ps1 -VMCount 1 -VMNamePrefix "web" -UseDifferencingDisk -BaseVhdxPath "C:\Images\WinServ2022_gen.vhdx" -SwitchName "NATSwitch" -CreateInternalSwitch

- Create 3 fresh VHDX-based VMs from scratch:
  .\create-vms.ps1 -VMCount 3 -VMNamePrefix "node" -DiskSizeGB 80 -MemoryStartupMB 8192 -ProcessorCount 4 -SwitchName "NATSwitch" -CreateInternalSwitch

- Example with admin password set via PowerShell Direct (only for Windows guests that support PSDirect):
  .\create-vms.ps1 -VMCount 1 -VMNamePrefix "win" -UseDifferencingDisk -BaseVhdxPath "C:\Images\WinServ2022_gen.vhdx" -AdminPassword "P@ssw0rd!" -CreateInternalSwitch

Notes and caveats
- PowerShell Direct (used to set Administrator password) only works for Windows guests with PSDirect support (Windows 10/Server 2016+). It requires that the VM is running on the same host and that the VM has PowerShell remoting enabled/usable by PSDirect.
- If you need fully automated Windows installs from ISO, you can create an `autounattend.xml` and attach it on a virtual DVD or floppy image; that is more complex and not included in this script. Tell me if you want an ISO-based unattended install workflow and I can add it.
- For Linux guests you'll likely want cloud-init or SSH key injection—this script does not configure cloud-init volumes. Use pre-prepared template VHDX images or let me add cloud-init support.

If you want I can:
- Add automatic autounattend.xml injection and ISO mounting to perform fully unattended Windows installs.
- Add PowerShell Direct provisioning steps to run a postinstall script on the guest (install tools, roles).
- Add support for joining a domain, setting custom networking beyond the default NAT, or generating/checkingpoints/backups.

Please tell me:
1) Which guest OS (Windows Server 2022, Windows Server 2019, Windows 10, Linux).
2) Whether you will provide a generalized base VHDX (and its path) or want to install from ISO.
3) Which networking option you prefer: external switch (give adapter name) or internal NAT (I will use 192.168.100.0/24 by default).
4) Any changes to default sizing (CPU/RAM/Disk) or number of VMs.

Once you confirm I’ll either:
- Adjust the script to your exact parameters, or
- If you prefer, produce an autounattend.iso-based workflow to perform fully automated installs from ISO.
```
