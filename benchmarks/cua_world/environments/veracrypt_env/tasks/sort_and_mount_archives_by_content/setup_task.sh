#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Sort and Mount Task ==="

# 1. Clean up previous run
echo "Cleaning up..."
veracrypt --text --dismount --non-interactive 2>/dev/null || true
rm -f /home/ga/Volumes/archive_*.hc
rm -f /tmp/ground_truth.json

# 2. Define content sources
# We use existing assets but rename them inside the volume to match task description
SRC_FINANCIAL="/workspace/assets/sample_data/FY2024_Revenue_Budget.csv"
SRC_LEGAL="/workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt"

# Create a dummy obsolete file
echo "These notes are from 2010 and can be discarded." > /tmp/obsolete_notes.txt
SRC_OBSOLETE="/tmp/obsolete_notes.txt"

# 3. Randomize assignment
# We have 3 files to assign to archive_A, archive_B, archive_C
# 0=Financial, 1=Legal, 2=Obsolete
ASSIGNMENTS=(0 1 2)
# Shuffle array
ASSIGNMENTS=($(shuf -e "${ASSIGNMENTS[@]}"))

echo "Assignment mapping (Hidden):"
echo "A -> ${ASSIGNMENTS[0]}"
echo "B -> ${ASSIGNMENTS[1]}"
echo "C -> ${ASSIGNMENTS[2]}"

# Save ground truth for debugging (verifier doesn't strictly need it if it checks content)
cat > /tmp/ground_truth_mapping.json << EOF
{
  "archive_A": "${ASSIGNMENTS[0]}",
  "archive_B": "${ASSIGNMENTS[1]}",
  "archive_C": "${ASSIGNMENTS[2]}",
  "legend": "0=Financial, 1=Legal, 2=Obsolete"
}
EOF

# 4. Create Volumes
PASSWORD="SortMe2024"
VOL_DIR="/home/ga/Volumes"
mkdir -p "$VOL_DIR"

create_and_fill_volume() {
    local vol_name=$1
    local type_idx=$2
    
    local vol_path="$VOL_DIR/$vol_name"
    local mount_tmp="/tmp/vc_setup_mnt_$vol_name"
    mkdir -p "$mount_tmp"

    echo "Creating $vol_name..."
    # Create volume
    veracrypt --text --create "$vol_path" \
        --size=5M \
        --password="$PASSWORD" \
        --encryption=AES \
        --hash=SHA-512 \
        --filesystem=FAT \
        --pim=0 \
        --keyfiles="" \
        --random-source=/dev/urandom \
        --non-interactive

    # Mount to populate
    veracrypt --text --mount "$vol_path" "$mount_tmp" \
        --password="$PASSWORD" \
        --pim=0 \
        --keyfiles="" \
        --protect-hidden=no \
        --non-interactive

    # Copy appropriate content
    if [ "$type_idx" -eq 0 ]; then
        cp "$SRC_FINANCIAL" "$mount_tmp/financial_records.csv"
        echo "Added financial records to $vol_name"
    elif [ "$type_idx" -eq 1 ]; then
        cp "$SRC_LEGAL" "$mount_tmp/legal_contract.txt"
        echo "Added legal contract to $vol_name"
    else
        cp "$SRC_OBSOLETE" "$mount_tmp/obsolete_notes.txt"
        echo "Added obsolete notes to $vol_name"
    fi

    # Sync and Dismount
    sync
    sleep 1
    veracrypt --text --dismount "$mount_tmp" --non-interactive
    rmdir "$mount_tmp"
}

create_and_fill_volume "archive_A.hc" "${ASSIGNMENTS[0]}"
create_and_fill_volume "archive_B.hc" "${ASSIGNMENTS[1]}"
create_and_fill_volume "archive_C.hc" "${ASSIGNMENTS[2]}"

# Clean up temp file
rm -f /tmp/obsolete_notes.txt

# 5. Launch VeraCrypt GUI for the agent
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 5
fi

# Ensure window is visible
if ! wait_for_window "VeraCrypt" 15; then
    echo "WARNING: VeraCrypt window may not be visible"
fi

# Maximize and focus
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Timestamp
date +%s > /tmp/task_start_time.txt

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="