```markdown
# install-hyperv.ps1 — Hyper‑V installer and basic vSwitch creator

What I created
- A single PowerShell script (install-hyperv.ps1) that:
  - Detects Windows Server vs Windows client Pro/Enterprise.
  - Verifies virtualization is enabled (best-effort).
  - Installs the Hyper-V role or enables Hyper-V feature and management tools.
  - Optionally creates an External vSwitch bound to a host NIC, or an Internal NAT vSwitch (with automatic host gateway and NAT).
  - Optionally reboots the host after installation.

Prerequisites
- Run as Administrator.
- Supported OS:
  - Windows Server (2012R2+), or
  - Windows 10/11 Pro, Enterprise (Home is not supported).
- Hardware virtualization (VT-x or AMD-V) must be enabled in BIOS/UEFI.
- Internet access for Windows Update / Optional Feature installation (on some client SKUs).
- PowerShell 5+ (built-in on supported Windows).

Basic usage examples
- Just install Hyper-V (no switches), show message to reboot:
  powershell -ExecutionPolicy Bypass -File .\install-hyperv.ps1

- Install Hyper-V and create an External vSwitch bound to the host "Ethernet" adapter, then reboot now:
  powershell -ExecutionPolicy Bypass -File .\install-hyperv.ps1 -SwitchType External -NetAdapterName "Ethernet" -InternalSwitchName "ExternalSwitch" -RebootNow

- Install Hyper-V and create an Internal NAT vSwitch on 192.168.100.0/24:
  powershell -ExecutionPolicy Bypass -File .\install-hyperv.ps1 -SwitchType InternalNAT -InternalSwitchName "NATSwitch" -InternalSubnet "192.168.100.0/24"

Notes, caveats, and troubleshooting
- Windows Home editions do not support Hyper-V; the script will abort if it detects "Home" in the OS name.
- If virtualization appears disabled, enable it in BIOS/UEFI and re-run. The script will warn and abort unless you pass -Force.
- On client OSes the feature enable commonly requires a reboot to complete — the script sets a flag and suggests a reboot. Use -RebootNow to reboot automatically.
- If the external adapter name isn't found, verify it with:
  Get-NetAdapter | Format-Table -AutoSize
- After installing, install Hyper-V Manager (Remote Server Administration Tools) if you plan to administer Hyper-V remotely; on servers the management tools are included with the role install above.
- Creating an External vSwitch may momentarily disrupt host network connectivity (network adapter is bound to the vSwitch).
- Internal NAT switch:
  - Host receives .1 on the internal vEthernet interface and NAT is created for the subnet.
  - VMs attached to that internal switch will get network via whatever method you use in the guest (static or DHCP if you provide one).

Security and production notes
- For production servers, review NIC teaming, VLAN configuration, and firewall/NAT rules—this script creates basic NAT for quick lab setups only.
- Consider separating management vs VM traffic on dedicated NICs for performance and security.

What’s next
- If you want, I can:
  - Add an option to automatically create a simple DHCP server for the internal NAT network (using a Windows service or a lightweight container).
  - Produce follow-up scripts to:
    - Create VMs (from generalized VHDX or new VHDX) — I already prepared an example previously and can wire the two together.
    - Provision Windows guests via PowerShell Direct or unattended ISO (autounattend.xml).
  - Create a PowerShell DSC or Ansible playbook to harden the host and configure role-specific networking.

If you'd like me to proceed, tell me:
1) Do you want an External switch (give host adapter name) or an Internal NAT switch (confirm subnet)? Or skip switch creation?
2) Should the script reboot automatically when finished (-RebootNow) or just prompt you to reboot?
3) Would you like me to also produce a companion script that creates VMs (using differencing disks or new VHDX) and attaches them to the created switch?

I'll then tailor the scripts or produce an integrated workflow (install → create switch → create VMs → provision guests).
```
