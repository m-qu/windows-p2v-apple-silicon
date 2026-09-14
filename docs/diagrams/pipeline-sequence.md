# Diagram: full pipeline sequence

Referenced from the [main README](../../README.md). The detailed version of the sequence diagram
there — every script from both `scripts/mac/` and `scripts/windows/`, in order, across both
machines.

```mermaid
sequenceDiagram
    autonumber
    participant Mac
    participant USB as FAT32 USB
    participant Win as Windows (WinRE)
    participant Ext as External NTFS drive

    Mac->>USB: copy scripts/windows/ onto the USB
    Note over Win: Boot from the USB into<br/>Troubleshoot -> Advanced options -> Command Prompt
    USB->>Win: 01-copy-to-external-drive.cmd
    Win->>Ext: copies scripts onto the external drive
    Win->>Ext: 02-capture-ffu.cmd (dism /Capture-FFU)
    Note over Win,Ext: Windows fully powered off during capture —<br/>this is the whole point
    Win->>Ext: 03-apply-ffu.cmd (create + attach VHDX,<br/>dism /Apply-FFU, detach)
    Win->>USB: 04-copy-logs-to-usb.cmd
    Note over Mac: Bring the USB back (small, fast)<br/>Bring the external drive back (large VHDX)
    Ext->>Mac: copy the resulting VHDX into IMAGE_DIR
    Mac->>Mac: 01-make-work-copy.sh (SHA-256 baseline + verified copy)
    Mac->>Mac: 02-check-all-hives.sh (read-only, Docker + libguestfs)
    Mac->>Mac: 04-boot-attempt-qemu.sh (OVMF + swtpm)
    Note over Mac: Reaches the Windows desktop
```
