```markdown
# Adding files to a Hyper‑V VM — methods & scripts

I included three approaches (and scripts) to add files to VMs on a Hyper‑V host. Choose based on your guest OS and network constraints.

Options summary
- PowerShell Direct (copy-vm-files-psdirect.ps1)
  - Best when the guest is Windows (Windows 10 / Server 2016+) and running on the same Hyper‑V host.
  - No network required.
  - Uses New-PSSession -VMName and Copy-Item -ToSession.
  - Requires credentials for an account inside the guest (e.g., Administrator).
  - Example:
    powershell -ExecutionPolicy Bypass -File .\copy-vm-files-psdirect.ps1 -VMName "winvm-1" -SourcePath "C:\Files\MyApp" -DestinationPath "C:\Temp\MyApp"

- Create-and-attach VHDX (create-and-attach-vhdx-with-files.ps1)
  - Works for Windows and Linux guests (they just get a new disk).
  - Script creates a dynamically expanding VHDX, mounts it on the host, formats, copies files, dismounts, and attaches to the VM.
  - Good for large payloads or when you prefer block device transfer.
  - Example:
    powershell -ExecutionPolicy Bypass -File .\create-and-attach-vhdx-with-files.ps1 -VMName "vm-1" -SourcePath "C:\Files\Payload" -VhdxPath "C:\HyperV\Disks\vm-1-data.vhdx" -VhdxSizeGB 40

- Host SMB share (create-host-smb-share.ps1)
  - Useful when the guest has network connectivity to the host.
  - Script creates a folder and SMB share on the host and prints connection instructions.
  - From a Windows guest: net use \\hostIP\ShareName
  - From a Linux guest: mount -t cifs //hostIP/ShareName /mnt -o username=...,password=...
  - Example:
    powershell -ExecutionPolicy Bypass -File .\create-host-smb-share.ps1 -ShareName "VMFiles" -HostFolder "C:\HyperV\Shared" -AllowEveryone

Which should I run or customize?
- If your guest is Windows and you have Administrator credentials for the guest: use PowerShell Direct (copy-vm-files-psdirect.ps1).
- If your guest is Linux or you want to deliver a disk image: use the VHDX approach.
- If your guest has network access to the host and you'd rather transfer over the network: use the SMB share.

Security notes
- Granting Everyone full access to an SMB share (-AllowEveryone) is insecure; use only in isolated lab environments.
- PowerShell Direct requires valid guest credentials; keep passwords secure.
- When attaching a VHDX, Windows guests may need to rescan disks or assign a drive letter inside the guest.

If you tell me:
- Which VM name and guest OS you are using, and
- Which method you prefer,

I can:
- Run through a concrete example for your VM (adjusting paths, sizes).
- Provide a variant that removes the VHDX after use, sets tighter SMB permissions, or uses a secure credential store.
```
