#!/bin/bash
echo "=== Setting up save_attachments_to_folder task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create target directory (ensure it is empty)
TARGET_DIR="/home/ga/Documents/ProjectFiles"
rm -rf "$TARGET_DIR" 2>/dev/null || true
mkdir -p "$TARGET_DIR"
chown ga:ga "$TARGET_DIR"

# Ensure Thunderbird is closed so we can inject the email
close_thunderbird
sleep 2

# Inject the email directly into the Inbox mbox file
echo "Injecting target email with attachments..."
python3 /workspace/tasks/save_attachments_to_folder/inject_email.py

# Remove the Inbox MSF index so Thunderbird rebuilds it and sees the new email
rm -f "/home/ga/.thunderbird/default-release/Mail/Local Folders/Inbox.msf" 2>/dev/null || true

# Start Thunderbird
start_thunderbird

# Wait for Thunderbird window to appear
wait_for_thunderbird_window 30

# Maximize the window for visibility
maximize_thunderbird
sleep 2

# Click slightly off-center to focus without altering state accidentally
su - ga -c "DISPLAY=:1 xdotool mousemove 500 100 click 1" || true
sleep 1

# Take initial state screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

# Verify screenshot was captured
if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo "=== Task setup complete ==="