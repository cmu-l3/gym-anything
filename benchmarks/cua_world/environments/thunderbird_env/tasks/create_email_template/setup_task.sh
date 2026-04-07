#!/bin/bash
echo "=== Setting up create_email_template task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

PROFILE_DIR="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="${PROFILE_DIR}/Mail/Local Folders"

# Ensure Thunderbird profile exists
if [ ! -d "$LOCAL_MAIL_DIR" ]; then
    mkdir -p "$LOCAL_MAIL_DIR"
    chown -R ga:ga "$PROFILE_DIR"
fi

# Clean state: Ensure Templates folder exists but is empty
echo "Clearing Templates folder for clean start..."
> "${LOCAL_MAIL_DIR}/Templates"
rm -f "${LOCAL_MAIL_DIR}/Templates.msf" 2>/dev/null || true
chown ga:ga "${LOCAL_MAIL_DIR}/Templates"

# Record initial mbox states
echo "$(grep -c "^From " "${LOCAL_MAIL_DIR}/Drafts" 2>/dev/null || echo "0")" > /tmp/initial_drafts_count.txt
echo "$(grep -c "^From " "${LOCAL_MAIL_DIR}/Sent" 2>/dev/null || echo "0")" > /tmp/initial_sent_count.txt

# Start Thunderbird if not running
if ! pgrep -f "thunderbird" > /dev/null; then
    echo "Starting Thunderbird..."
    su - ga -c "DISPLAY=:1 thunderbird -profile /home/ga/.thunderbird/default-release > /dev/null 2>&1 &"
fi

# Wait for Thunderbird window to appear
echo "Waiting for Thunderbird window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Mozilla Thunderbird"; then
        echo "Thunderbird window detected."
        break
    fi
    sleep 1
done

# Give UI a moment to stabilize
sleep 3

# Maximize and focus Thunderbird
DISPLAY=:1 wmctrl -r "Mozilla Thunderbird" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Thunderbird" 2>/dev/null || true

# Close any accidental compose windows that might be open
DISPLAY=:1 wmctrl -c "Write:" 2>/dev/null || true

# Click center of screen to ensure desktop/app is focused
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state screenshot..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="