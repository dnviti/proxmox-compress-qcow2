# Proxmox VM Disk Compression Script

A Bash script to compress a Proxmox Virtual Machine's disk by converting it to a compressed QCOW2 image, saving disk space in the process. The script handles disks not already in QCOW2 format by moving them to a compatible storage and converting them during the move.

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Example](#example)
- [Important Notes](#important-notes)
- [Contributing](#contributing)
- [License](#license)

---

## Features

- Detects VM type (supports QEMU VMs)
- Checks disk format and storage type
- Moves and converts disks not in QCOW2 format to compatible storage
- Compresses QCOW2 disks to save space
- Interactive prompts for user confirmation
- Option to delete old disk volumes to free up space
- Provides detailed feedback and progress information

---

## Requirements

- Proxmox VE environment
- Bash shell
- `qm` command-line tool (included in Proxmox)
- `qemu-img` utility
- Sufficient permissions to manage VMs and storage (usually root)

---

## Installation

1. **Download the Script**

   Download the `compress_vm_disk.sh` script to your Proxmox server.

2. **Make the Script Executable**

   ```bash
   chmod +x compress_vm_disk.sh
   ```

---

## Usage

```bash
./compress_vm_disk.sh <VMID> [DISKID]
```

- `<VMID>`: The ID of the VM you want to compress the disk for.
- `[DISKID]`: (Optional) The ID of the disk to compress (defaults to `0`).

**Note:** Run the script as root or a user with sufficient privileges.

---

## Example

### Compressing Disk 0 of VM 106

```bash
./compress_vm_disk.sh 106
```

### Sample Output

```
🖥️  Detected VM Type: qemu
📦 Current Storage: nvme01
🗄️  Storage Type: lvmthin
✅ Disk Located: /dev/nvme01/vm-106-disk-0
ℹ️  Disk Format: raw
❌ Disk is NOT in QCOW2 format.
⚠️  Do you want to move the disk to a QCOW2-compatible storage? (y/N): y
📂 Available storages that support QCOW2:
1) local
2) nfs-storage
#? 1
📁 Selected storage: local
🔄 Moving and converting disk to QCOW2 format...
✅ Disk moved and converted successfully.
🗑️  The original disk volume remains on storage 'nvme01'.
🗑️  Do you want to delete the old disk volume? (y/N): y
🗑️  Deleting old volume...
✅ Old volume deleted.
📏 Initial Disk Size: 51200 MB
⚠️  Proceed with compression? (y/N): y
⏳ Stopping VM 106...
🚀 Restarting VM 106...
🎉 Compression Successful!
📏 Original Size: 51200 MB
📉 Compressed Size: 25600 MB
💾 Space Saved: 25600 MB (50%)
🗑️  Delete the backup of the original disk? (y/N): n
💾 Backup retained at /var/lib/vz/images/106/vm-106-disk-0.qcow2.old
```

---

## Important Notes

- **Data Safety:**
  - **Backup your VM** before performing disk operations.
  - Test the VM thoroughly after moving and compressing the disk.
- **Storage Selection:**
  - Only storages supporting QCOW2 format will be listed.
  - Ensure the selected storage has enough space for the disk.
- **Cleaning Up:**
  - Deleting the old disk volume frees up space.
  - Retaining the backup of the original disk (`*.old`) allows you to restore if needed.
- **Permissions:**
  - Run the script with root permissions or as a user with sufficient privileges.
- **Error Handling:**
  - The script checks for errors at each critical step and exits if an error occurs.
  - If an operation fails, manual cleanup may be necessary.
- **Compatibility:**
  - Designed for Proxmox VE environments.
  - Adjustments may be needed for different environments or storage configurations.
- **VM Downtime:**
  - The VM will be stopped during the compression process.
  - Plan for VM downtime accordingly.

---

## Script Breakdown

### 1. Detecting VM and Disk Information

- **VM Detection:**
  - Checks if the VM ID exists and is a QEMU VM.
- **Disk Information:**
  - Retrieves the disk configuration from Proxmox.
  - Extracts storage name, volume, and path.
  - Determines storage type and disk format.

### 2. Handling Non-QCOW2 Disks

- **Storage Type Check:**
  - Identifies if the disk is on `lvm` or `lvmthin` storage (raw format).
- **Moving and Converting Disk:**
  - Offers to move the disk to a QCOW2-compatible storage.
  - Lists available storages that support QCOW2.
  - Uses `qm move_disk` to move and convert the disk.

### 3. Compressing the Disk

- **User Confirmation:**
  - Asks for confirmation before proceeding with compression.
- **Stopping the VM:**
  - Gracefully shuts down the VM, with a timeout and force-stop if necessary.
- **Compression Process:**
  - Uses `qemu-img convert` with compression enabled.
  - Checks for successful compression.

### 4. Finalizing and Cleanup

- **Replacing the Disk:**
  - Backs up the original disk (`*.old`).
  - Replaces it with the compressed disk.
- **Restarting the VM:**
  - Starts the VM after disk replacement.
- **Space Savings Calculation:**
  - Displays original and compressed sizes.
  - Calculates and shows space saved.
- **Backup Deletion:**
  - Offers to delete the backup of the original disk.

---

## Contributing

Contributions are welcome! Please open an issue or submit a pull request with improvements or bug fixes.

---

## License

This script is released under the [MIT License](LICENSE).

---

## Disclaimer

This script is provided "as is" without any warranties. Use it at your own risk. Always ensure that you have backups before performing operations that can affect your data.

---

Feel free to customize and enhance the script to suit your specific needs. If you encounter any issues or have suggestions for improvements, please let us know.

Happy compressing!
