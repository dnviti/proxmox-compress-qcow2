#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 <VMID> [DISKID]"
    exit 1
}

# Get VMID and DISKID from arguments
QMID=$1
DISKID=${2:-0}  # Default DISKID to "0"

if [[ ! "$QMID" =~ ^[0-9]+$ ]]; then
    echo "❌ Error: VMID must be a number."
    usage
fi

# Detect VM type (QEMU only)
if qm status "$QMID" >/dev/null 2>&1; then
    VM_TYPE="qemu"
else
    echo "❌ Error: VM $QMID not found or is not a QEMU VM."
    exit 1
fi
echo "🖥️  Detected VM Type: $VM_TYPE"

# Get the disk line from the config
DISK_LINE=$(qm config "$QMID" | grep -E "^(scsi${DISKID}|virtio${DISKID}|ide${DISKID}|sata${DISKID}|nvme${DISKID}):")
if [ -z "$DISK_LINE" ]; then
    echo "❌ Error: Could not find disk definition for VM $QMID Disk $DISKID."
    exit 1
fi

# Extract the disk configuration
DISK_BUS=$(echo "$DISK_LINE" | cut -d':' -f1)
DISK_CONF=$(echo "$DISK_LINE" | cut -d' ' -f2-)

# Extract the storage and volume names
STORAGE=$(echo "$DISK_CONF" | awk -F ':' '{print $1}')
VOLUME=$(echo "$DISK_CONF" | awk -F ':' '{print $2}' | cut -d ',' -f1)
echo "📦 Current Storage: $STORAGE"

# Get storage type
STORAGE_TYPE=$(pvesm status -storage "$STORAGE" | awk 'NR>1 {print $2}')
if [ -z "$STORAGE_TYPE" ]; then
    echo "❌ Error: Could not determine storage type for $STORAGE."
    exit 1
fi
echo "🗄️  Storage Type: $STORAGE_TYPE"

# Get the disk path using pvesm
DISK_PATH=$(pvesm path "$STORAGE:$VOLUME" 2>/dev/null)
if [ -z "$DISK_PATH" ]; then
    echo "❌ Error: Could not resolve disk path."
    exit 1
fi
echo "✅ Disk Located: $DISK_PATH"

# Determine disk format based on storage type
if [[ "$STORAGE_TYPE" == "lvm" ]] || [[ "$STORAGE_TYPE" == "lvmthin" ]]; then
    DISK_FORMAT="raw"
else
    # Get current disk format using qemu-img
    DISK_FORMAT=$(qemu-img info "$DISK_PATH" 2>/dev/null | grep "file format" | awk '{print $3}')
    if [ -z "$DISK_FORMAT" ]; then
        echo "❌ Error: Unable to determine disk format."
        exit 1
    fi
fi
echo "ℹ️  Disk Format: $DISK_FORMAT"

# Function to list storages supporting QCOW2
list_qcow2_storages() {
    pvesm status --enabled 1 | awk '$2 ~ /dir|nfs|zfs/ {print $1}'
}

# Check disk format
if [ "$DISK_FORMAT" != "qcow2" ]; then
    echo "❌ Disk is NOT in QCOW2 format."

    # Ask user if they want to move the disk to a QCOW2-compatible storage
    read -p "⚠️  Do you want to move the disk to a QCOW2-compatible storage? (y/N): " CONFIRM_MOVE
    if [[ ! "$CONFIRM_MOVE" =~ ^[Yy]$ ]]; then
        echo "❌ Cannot proceed without QCOW2 disk. Exiting."
        exit 1
    fi

    # List available storages that support QCOW2
    echo "📂 Available storages that support QCOW2:"
    QCOW2_STORAGES=$(pvesm status --enabled 1 | awk '$2 ~ /dir|nfs|zfs/ {print $1}')

    # Check if there are any suitable storages
    if [ -z "$QCOW2_STORAGES" ]; then
        echo "❌ No storages available that support QCOW2 format."
        exit 1
    fi

    # Display the list with numbers
    select TARGET_STORAGE in $QCOW2_STORAGES; do
        if [ -n "$TARGET_STORAGE" ]; then
            echo "📁 Selected storage: $TARGET_STORAGE"
            break
        else
            echo "❌ Invalid selection."
        fi
    done

    # Move the disk to the selected storage with conversion to QCOW2
    echo "🔄 Moving and converting disk to QCOW2 format..."
    qm move_disk "$QMID" "$DISK_BUS" "$TARGET_STORAGE" --format qcow2
    if [ $? -ne 0 ]; then
        echo "❌ Error: Disk move and conversion failed."
        exit 1
    fi
    echo "✅ Disk moved and converted successfully."

    # Get updated disk path and storage type
    DISK_LINE=$(qm config "$QMID" | grep "^${DISK_BUS}:")
    DISK_CONF=$(echo "$DISK_LINE" | cut -d' ' -f2-)
    STORAGE=$(echo "$DISK_CONF" | awk -F ':' '{print $1}')
    VOLUME=$(echo "$DISK_CONF" | awk -F ':' '{print $2}' | cut -d ',' -f1)
    DISK_PATH=$(pvesm path "$STORAGE:$VOLUME" 2>/dev/null)
    STORAGE_TYPE=$(pvesm status -storage "$STORAGE" | awk 'NR>1 {print $2}')
    DISK_FORMAT="qcow2"  # Now it's qcow2 after conversion

    # Ask if the user wants to remove the old disk
    echo "🗑️  The original disk volume remains on storage '$STORAGE'."
    read -p "🗑️  Do you want to delete the old disk volume? (y/N): " DELETE_OLD
    if [[ "$DELETE_OLD" =~ ^[Yy]$ ]]; then
        # Remove the old volume
        echo "🗑️  Deleting old volume..."
        pvesm free "$STORAGE:$VOLUME"
        echo "✅ Old volume deleted."
    else
        echo "💾 Old volume retained."
    fi
else
    echo "✔️  Disk is already in QCOW2 format."
fi

# Confirm before compression
INITIAL_SIZE_BYTES=$(qemu-img measure "$DISK_PATH" 2>/dev/null | grep 'required size:' | awk '{print $3}')
if [ -z "$INITIAL_SIZE_BYTES" ]; then
    # Fall back to 'du' if qemu-img measure fails
    INITIAL_SIZE_BYTES=$(du -b "$DISK_PATH" | awk '{print $1}')
fi
INITIAL_SIZE_MB=$((INITIAL_SIZE_BYTES / (1024 * 1024)))
echo "📏 Initial Disk Size: ${INITIAL_SIZE_MB} MB"

read -p "⚠️  Proceed with compression? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "❌ Compression aborted."
    exit 0
fi

# Stop VM before compression
echo "⏳ Stopping VM $QMID..."
qm shutdown "$QMID"
TIMEOUT=60  # seconds
while [ $TIMEOUT -gt 0 ]; do
    VM_STATUS=$(qm status "$QMID" | awk '{print $2}')
    if [ "$VM_STATUS" == "stopped" ]; then
        break
    fi
    sleep 1
    TIMEOUT=$((TIMEOUT - 1))
done
if [ $TIMEOUT -eq 0 ]; then
    echo "⚠️  VM did not shut down gracefully. Forcing stop..."
    qm stop "$QMID"
fi

# Compress the disk
echo "💾 Compressing disk..."
qemu-img convert -O qcow2 -c "$DISK_PATH" "${DISK_PATH}.compressed"
if [ $? -ne 0 ]; then
    echo "❌ Error: Disk compression failed."
    exit 1
fi
echo "✅ Compression complete!"

# Get compressed size
COMPRESSED_SIZE_BYTES=$(qemu-img measure "${DISK_PATH}.compressed" 2>/dev/null | grep 'required size:' | awk '{print $3}')
if [ -z "$COMPRESSED_SIZE_BYTES" ]; then
    # Fall back to 'du' if qemu-img measure fails
    COMPRESSED_SIZE_BYTES=$(du -b "${DISK_PATH}.compressed" | awk '{print $1}')
fi
COMPRESSED_SIZE_MB=$((COMPRESSED_SIZE_BYTES / (1024 * 1024)))

# Confirm replacement
read -p "⚠️  Replace old disk with compressed version? (y/N): " CONFIRM_REPLACE
if [[ ! "$CONFIRM_REPLACE" =~ ^[Yy]$ ]]; then
    echo "❌ Skipping replacement. Compressed file remains: ${DISK_PATH}.compressed"
    exit 0
fi

# Replace old disk
echo "🔄 Replacing old disk..."
mv "$DISK_PATH" "${DISK_PATH}.old"
mv "${DISK_PATH}.compressed" "$DISK_PATH"
echo "✅ Old disk backed up as ${DISK_PATH}.old"

# Restart VM
echo "🚀 Restarting VM $QMID..."
qm start "$QMID"

# Display space savings
if [ $INITIAL_SIZE_MB -gt 0 ]; then
    SAVINGS=$((INITIAL_SIZE_MB - COMPRESSED_SIZE_MB))
    PERCENT_SAVINGS=$((SAVINGS * 100 / INITIAL_SIZE_MB))
else
    SAVINGS=0
    PERCENT_SAVINGS=0
fi
echo "🎉 Compression Successful!"
echo "📏 Original Size: ${INITIAL_SIZE_MB} MB"
echo "📉 Compressed Size: ${COMPRESSED_SIZE_MB} MB"
echo "💾 Space Saved: ${SAVINGS} MB (${PERCENT_SAVINGS}%)"

# Option to delete old disk
read -p "🗑️  Delete the backup of the original disk? (y/N): " DELETE_BACKUP
if [[ "$DELETE_BACKUP" =~ ^[Yy]$ ]]; then
    rm -f "${DISK_PATH}.old"
    echo "🗑️  Backup deleted."
else
    echo "💾 Backup retained at ${DISK_PATH}.old"
fi
