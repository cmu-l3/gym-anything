#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Recover Volume Task ==="

# 1. Clean up previous state
echo "Cleaning up..."
veracrypt --text --dismount --non-interactive 2>/dev/null || true
rm -f /home/ga/Volumes/project_archive.hc
rm -rf /home/ga/Documents/candidates
mkdir -p /home/ga/Documents/candidates
rm -f /home/ga/Documents/recovered_token.txt
rm -f /home/ga/Documents/correct_keyfile_name.txt

# 2. Prepare candidate files (Real Data: System Python scripts)
echo "Generating candidate keyfiles..."
# Copy ~20 random python files from system lib to ensure real file content
find /usr/lib/python3* -name "*.py" -type f 2>/dev/null | head -n 200 | shuf | head -n 20 | while read f; do
    cp "$f" "/home/ga/Documents/candidates/"
done

# Fallback if copy failed (e.g. minimal container)
if [ "$(ls -1 /home/ga/Documents/candidates | wc -l)" -lt 5 ]; then
    echo "Fallback: creating dummy scripts"
    for i in {1..20}; do
        echo "import os; print('Script $i')" > "/home/ga/Documents/candidates/script_$i.py"
        # Add random entropy
        head -c 100 /dev/urandom >> "/home/ga/Documents/candidates/script_$i.py"
    done
fi

# 3. Select the "True" keyfile
KEYFILE_PATH=$(find "/home/ga/Documents/candidates" -type f | shuf -n 1)
KEYFILE_NAME=$(basename "$KEYFILE_PATH")
echo "Selected keyfile: $KEYFILE_NAME"

# Save ground truth to a hidden location (root owned, agent can't easily see without sudo)
echo "$KEYFILE_NAME" > /var/lib/app/ground_truth_keyname.txt
chmod 644 /var/lib/app/ground_truth_keyname.txt # Readable for export script

# 4. Create the Volume using this keyfile
VOL_PATH="/home/ga/Volumes/project_archive.hc"
TEMP_MOUNT="/tmp/vc_setup_mount"
mkdir -p "$TEMP_MOUNT"

echo "Creating encrypted volume..."
# Create volume with both password and keyfile
veracrypt --text --create "$VOL_PATH" \
    --size=10M \
    --password='DevOps2024' \
    --keyfiles="$KEYFILE_PATH" \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --random-source=/dev/urandom \
    --non-interactive

# 5. Populate volume with secret token and decoy data
echo "Populating volume..."
veracrypt --text --mount "$VOL_PATH" "$TEMP_MOUNT" \
    --password='DevOps2024' \
    --keyfiles="$KEYFILE_PATH" \
    --pim=0 \
    --protect-hidden=no \
    --non-interactive

# Generate secret token
TOKEN="TOKEN-$(date +%s)-$RANDOM-SECURE"
echo "$TOKEN" > "$TEMP_MOUNT/secret_token.txt"

# Save token ground truth
echo "$TOKEN" > /var/lib/app/ground_truth_token.txt
chmod 644 /var/lib/app/ground_truth_token.txt

# Add realistic decoy data
if [ -f "/workspace/assets/sample_data/FY2024_Revenue_Budget.csv" ]; then
    cp "/workspace/assets/sample_data/FY2024_Revenue_Budget.csv" "$TEMP_MOUNT/project_budget.csv"
fi
echo "Project Architecture v2.0" > "$TEMP_MOUNT/README.md"

# Dismount
veracrypt --text --dismount "$TEMP_MOUNT" --non-interactive
sleep 1
rmdir "$TEMP_MOUNT" 2>/dev/null || true

# 6. UI Setup
# Ensure VeraCrypt is running
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
fi

if ! wait_for_window "VeraCrypt" 15; then
    echo "WARNING: VeraCrypt window may not be visible"
fi

# Open the candidates folder so agent sees the problem
su - ga -c "DISPLAY=:1 xdg-open /home/ga/Documents/candidates" &
sleep 2

# Maximize VeraCrypt
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r "VeraCrypt" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Record start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="