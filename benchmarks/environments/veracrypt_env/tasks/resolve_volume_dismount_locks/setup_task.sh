#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Resolve Volume Dismount Locks Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Constants
VOL_PATH="/home/ga/Volumes/HR_Archive.hc"
MOUNT_POINT="/home/ga/MountPoints/HR_Archive"
PASSWORD="SecureHR2024"

# 1. Clean up previous state
# Kill potential blocking processes from previous runs
pkill -f "lock_script.py" 2>/dev/null || true
pkill -f "tail -f $MOUNT_POINT" 2>/dev/null || true
# We be careful with gedit to not kill other instances if possible, but for this env it's fine
pkill -f "gedit $MOUNT_POINT" 2>/dev/null || true

# Dismount if mounted
veracrypt --text --dismount "$MOUNT_POINT" --non-interactive 2>/dev/null || true
veracrypt --text --dismount "$VOL_PATH" --non-interactive 2>/dev/null || true
sleep 2

# 2. Create Volume if it doesn't exist
if [ ! -f "$VOL_PATH" ]; then
    echo "Creating HR_Archive volume..."
    veracrypt --text --create "$VOL_PATH" \
        --size=20M \
        --password="$PASSWORD" \
        --encryption=AES \
        --hash=SHA-512 \
        --filesystem=FAT \
        --pim=0 \
        --keyfiles="" \
        --random-source=/dev/urandom \
        --non-interactive
fi

# 3. Mount the volume
echo "Mounting volume..."
mkdir -p "$MOUNT_POINT"
veracrypt --text --mount "$VOL_PATH" "$MOUNT_POINT" \
    --password="$PASSWORD" \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive

# Verify mount
if ! mountpoint -q "$MOUNT_POINT"; then
    echo "ERROR: Failed to mount volume"
    exit 1
fi

# 4. Populate with dummy files
echo "Populating volume..."
echo "Confidential Employee Data" > "$MOUNT_POINT/employee_list.txt"
echo "Server Logs 2024" > "$MOUNT_POINT/server.log"
echo "Active Process Data" > "$MOUNT_POINT/active_data.dat"

# 5. Start Blocking Processes
echo "Starting blocking processes..."

# Process 1: gedit (GUI Text Editor)
# Run as ga user
su - ga -c "DISPLAY=:1 gedit '$MOUNT_POINT/employee_list.txt' &"
PID_GEDIT=$!
sleep 2

# Process 2: tail (Background CLI tool)
su - ga -c "tail -f '$MOUNT_POINT/server.log' &"
PID_TAIL=$!

# Process 3: python script (Active writer)
SCRIPT_PATH="/tmp/lock_script.py"
cat > "$SCRIPT_PATH" << EOF
import time
import os

file_path = "$MOUNT_POINT/active_data.dat"
try:
    with open(file_path, "a") as f:
        while True:
            f.write(".")
            f.flush()
            time.sleep(1)
except:
    pass
EOF
chmod +x "$SCRIPT_PATH"
su - ga -c "python3 '$SCRIPT_PATH' &"
PID_PYTHON=$!

# Save PIDs for verification (hidden from agent)
echo "$PID_GEDIT" > /tmp/blocking_pids.txt
echo "$PID_TAIL" >> /tmp/blocking_pids.txt
echo "$PID_PYTHON" >> /tmp/blocking_pids.txt

echo "Blocking processes started: gedit ($PID_GEDIT), tail ($PID_TAIL), python ($PID_PYTHON)"

# 6. Ensure VeraCrypt GUI is running and visible
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt GUI..."
    su - ga -c "DISPLAY=:1 veracrypt &"
fi

wait_for_window "VeraCrypt" 20
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="