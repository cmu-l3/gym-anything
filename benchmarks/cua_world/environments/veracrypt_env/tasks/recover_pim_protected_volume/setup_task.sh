#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up PIM Recovery Task ==="

# Record start time
date +%s > /tmp/task_start_time.txt

# Directories
EVIDENCE_DIR="/home/ga/Evidence"
DOCS_DIR="/home/ga/Documents"
MOUNT_POINT="/tmp/vc_setup_mount"
TRUTH_DIR="/var/lib/veracrypt_task"

mkdir -p "$EVIDENCE_DIR" "$DOCS_DIR" "$MOUNT_POINT" "$TRUTH_DIR"

# Clean up previous runs
rm -f "$EVIDENCE_DIR/locked_project.hc"
rm -f "$DOCS_DIR/recovered_specs.txt"
rm -f "$DOCS_DIR/found_pim.txt"
veracrypt --text --dismount --force --non-interactive 2>/dev/null || true

# 1. Generate Random PIM (1-50) and Secret
TARGET_PIM=$(( ( RANDOM % 50 ) + 1 ))
SECRET_CODE="CONFIDENTIAL_$(date +%s)_$(head -c 4 /dev/urandom | xxd -p)"
PASSWORD="ProjectAlpha2024!"

echo "Target PIM: $TARGET_PIM"
echo "Secret: $SECRET_CODE"

# Save ground truth (root only)
cat > "$TRUTH_DIR/truth.json" << EOF
{
    "pim": $TARGET_PIM,
    "secret_string": "$SECRET_CODE"
}
EOF
chmod 600 "$TRUTH_DIR/truth.json"

# 2. Create the PIM-protected volume
# Using --pim switch to set non-default PIM
echo "Creating encrypted volume..."
veracrypt --text --create "$EVIDENCE_DIR/locked_project.hc" \
    --size=5M \
    --password="$PASSWORD" \
    --pim="$TARGET_PIM" \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --keyfiles="" \
    --random-source=/dev/urandom \
    --non-interactive

# 3. Mount to populate data
echo "Populating volume..."
veracrypt --text --mount "$EVIDENCE_DIR/locked_project.hc" "$MOUNT_POINT" \
    --password="$PASSWORD" \
    --pim="$TARGET_PIM" \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive

# 4. Add secret file and filler data
if mountpoint -q "$MOUNT_POINT"; then
    # The secret file
    echo "PROJECT SPECS - TOP SECRET" > "$MOUNT_POINT/project_specs.txt"
    echo "--------------------------" >> "$MOUNT_POINT/project_specs.txt"
    echo "ID: $SECRET_CODE" >> "$MOUNT_POINT/project_specs.txt"
    echo "Do not distribute." >> "$MOUNT_POINT/project_specs.txt"

    # Filler
    echo "Meeting notes 2024..." > "$MOUNT_POINT/notes.txt"
    
    sync
    sleep 2
    veracrypt --text --dismount "$MOUNT_POINT" --non-interactive
else
    echo "ERROR: Failed to mount volume during setup!"
    exit 1
fi

rmdir "$MOUNT_POINT" 2>/dev/null || true

# 5. Fix permissions
chown -R ga:ga "$EVIDENCE_DIR"
chown -R ga:ga "$DOCS_DIR"

# 6. Ensure VeraCrypt GUI is open (agent expects it, even if they use CLI)
if ! is_veracrypt_running; then
    su - ga -c "DISPLAY=:1 veracrypt &"
fi
wait_for_window "VeraCrypt" 10
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r "VeraCrypt" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="