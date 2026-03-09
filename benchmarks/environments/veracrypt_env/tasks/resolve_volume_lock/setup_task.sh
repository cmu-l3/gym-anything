#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Resolve Volume Lock Task ==="

# 1. Install diagnostic tools if missing (ensure agent has tools to solve it)
if ! command -v lsof >/dev/null; then
    apt-get update && apt-get install -y lsof psmisc
fi

# 2. Clean up previous runs
veracrypt --text --dismount --force --non-interactive 2>/dev/null || true
rm -f /home/ga/Volumes/log_storage.hc 2>/dev/null || true
rm -f /home/ga/Documents/lock_incident.txt 2>/dev/null || true
rm -f /tmp/.ground_truth_pid 2>/dev/null || true

# 3. Create the volume
VOL_PATH="/home/ga/Volumes/log_storage.hc"
MOUNT_POINT="/home/ga/MountPoints/secure_logs"
mkdir -p "$MOUNT_POINT"

echo "Creating volume..."
veracrypt --text --create "$VOL_PATH" \
    --size=10M \
    --password='LogAccess2024' \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles='' \
    --random-source=/dev/urandom \
    --non-interactive

# 4. Mount the volume
echo "Mounting volume..."
veracrypt --text --mount "$VOL_PATH" "$MOUNT_POINT" \
    --password='LogAccess2024' \
    --pim=0 \
    --keyfiles='' \
    --protect-hidden=no \
    --non-interactive

# 5. Populate with dummy data
echo "Generating logs..."
for i in {1..5}; do
    echo "[$(date)] Access log entry $i" >> "$MOUNT_POINT/access.log"
    echo "[$(date)] Error log entry $i" >> "$MOUNT_POINT/error.log"
done
sync

# 6. Start the locking process
# We use 'tail -f' on a file inside the volume to keep it busy
# Run as 'ga' user so standard tools can see it easily
echo "Starting locking process..."
su - ga -c "nohup tail -f $MOUNT_POINT/access.log > /dev/null 2>&1 & echo \$! > /tmp/.ground_truth_pid"
sleep 2

# Verify lock is active
LOCK_PID=$(cat /tmp/.ground_truth_pid)
if ps -p "$LOCK_PID" > /dev/null; then
    echo "Lock established. PID: $LOCK_PID"
else
    echo "ERROR: Locking process failed to start."
    exit 1
fi

# 7. Start VeraCrypt GUI
if ! is_veracrypt_running; then
    su - ga -c "DISPLAY=:1 veracrypt &"
fi
wait_for_window "VeraCrypt" 15
maximize_window "VeraCrypt" 2>/dev/null || true

# 8. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 9. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Volume: $VOL_PATH"
echo "Mount Point: $MOUNT_POINT"
echo "Locking PID: $LOCK_PID (Hidden from agent)"