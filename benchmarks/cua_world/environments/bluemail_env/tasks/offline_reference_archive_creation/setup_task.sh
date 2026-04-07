#!/bin/bash
echo "=== Setting up Offline Reference Archive Creation task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up target directory to ensure agent actually creates it
TARGET_DIR="/home/ga/Documents/OfflineDocs"
if [ -d "$TARGET_DIR" ]; then
    echo "Cleaning up existing target directory..."
    rm -rf "$TARGET_DIR"
fi

# Ensure parent Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 2. Ensure mail system is ready (Dovecot/Postfix)
# This is critical for BlueMail to see emails
systemctl restart dovecot 2>/dev/null || dovecot 2>/dev/null || true
sleep 2

# 3. Ensure BlueMail is running
if ! is_bluemail_running; then
    echo "Starting BlueMail..."
    start_bluemail
fi

# 4. Wait for window and maximize
wait_for_bluemail_window 60
sleep 2
maximize_bluemail

# 5. Record initial state of Documents folder (for anti-gaming)
ls -R /home/ga/Documents > /tmp/initial_documents_listing.txt

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="