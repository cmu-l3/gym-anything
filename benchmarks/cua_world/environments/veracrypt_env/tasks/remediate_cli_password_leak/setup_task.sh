#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Remediate CLI Password Leak Task ==="

# 1. Generate a random "leaked" password
# We use a random element so the agent MUST look at the history, cannot guess
RANDOM_SUFFIX=$(shuf -i 1000-9999 -n 1)
LEAKED_PASSWORD="Ops${RANDOM_SUFFIX}Secret!"
echo "$LEAKED_PASSWORD" > /tmp/original_leaked_password.txt
chmod 600 /tmp/original_leaked_password.txt

echo "Generated leaked password: $LEAKED_PASSWORD"

# 2. Create the encrypted volume with this password
VOLUME_PATH="/home/ga/Volumes/internal_ops.hc"
rm -f "$VOLUME_PATH" 2>/dev/null || true

echo "Creating volume at $VOLUME_PATH..."
veracrypt --text --create "$VOLUME_PATH" \
    --size=10M \
    --password="$LEAKED_PASSWORD" \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=FAT \
    --pim=0 \
    --keyfiles="" \
    --random-source=/dev/urandom \
    --non-interactive

# Verify volume creation
if [ ! -f "$VOLUME_PATH" ]; then
    echo "ERROR: Failed to create volume"
    exit 1
fi

# 3. Inject the leak into .bash_history
# We simulate a user who mounted it via CLI and exposed the password
HISTORY_FILE="/home/ga/.bash_history"
# Ensure history file exists
touch "$HISTORY_FILE"

# Add some noise before
echo "ls -la /home/ga/Volumes/" >> "$HISTORY_FILE"
echo "df -h" >> "$HISTORY_FILE"
# The leak
echo "veracrypt --text --mount $VOLUME_PATH /mnt/tmp --password='$LEAKED_PASSWORD' --pim=0 --protect-hidden=no" >> "$HISTORY_FILE"
# Add some noise after
echo "ls /mnt/tmp" >> "$HISTORY_FILE"
echo "veracrypt -d /mnt/tmp" >> "$HISTORY_FILE"

# Fix permissions
chown ga:ga "$HISTORY_FILE"
chmod 600 "$HISTORY_FILE"

# 4. Standard Environment Setup
# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure VeraCrypt GUI is running (agent might use GUI to change password)
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 3
fi

# Focus VeraCrypt
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="