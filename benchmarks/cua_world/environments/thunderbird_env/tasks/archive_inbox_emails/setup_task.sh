#!/bin/bash
set -e

echo "=== Setting up archive_inbox_emails task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Define paths
PROFILE_DIR="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="${PROFILE_DIR}/Mail/Local Folders"
PREFS_FILE="${PROFILE_DIR}/prefs.js"
INBOX_PATH="${LOCAL_MAIL_DIR}/Inbox"

# Ensure Thunderbird is closed before modifying files
if pgrep -f "thunderbird" > /dev/null; then
    echo "Closing running Thunderbird instance..."
    su - ga -c "DISPLAY=:1 wmctrl -c 'Mozilla Thunderbird'" 2>/dev/null || true
    sleep 3
    pkill -f "thunderbird" 2>/dev/null || true
    sleep 2
fi

# Ensure Archives folder is completely removed (clean slate)
rm -f "${LOCAL_MAIL_DIR}/Archives" 2>/dev/null || true
rm -f "${LOCAL_MAIL_DIR}/Archives.msf" 2>/dev/null || true
rm -rf "${LOCAL_MAIL_DIR}/Archives.sbd" 2>/dev/null || true

# Remove any existing archive_granularity settings so the agent MUST set it
if [ -f "$PREFS_FILE" ]; then
    sed -i '/archive_granularity/d' "$PREFS_FILE" 2>/dev/null || true
fi

# Record initial Inbox count and sample subjects (for anti-gaming preservation check)
if [ -f "$INBOX_PATH" ]; then
    INITIAL_COUNT=$(grep -c "^From " "$INBOX_PATH" 2>/dev/null || echo "0")
    echo "$INITIAL_COUNT" > /tmp/initial_inbox_count.txt
    
    # Save a random sample of 5 subjects to verify they make it to the Archives folder
    grep -i "^Subject:" "$INBOX_PATH" 2>/dev/null | head -5 | sed 's/^Subject: *//i' | tr -d '\r' > /tmp/initial_inbox_subjects.txt
else
    echo "0" > /tmp/initial_inbox_count.txt
    touch /tmp/initial_inbox_subjects.txt
fi

echo "Initial Inbox count: $(cat /tmp/initial_inbox_count.txt)"
echo "Archives folder removed. Preferences cleared."

# Start Thunderbird
echo "Starting Thunderbird..."
su - ga -c "DISPLAY=:1 thunderbird -profile /home/ga/.thunderbird/default-release > /tmp/thunderbird_ga.log 2>&1 &"

# Wait for Thunderbird window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "thunderbird"; then
        echo "Thunderbird window detected"
        break
    fi
    sleep 1
done

# Give Thunderbird time to index and settle
sleep 5

# Maximize and focus Thunderbird
DISPLAY=:1 wmctrl -r "Mozilla Thunderbird" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Thunderbird" 2>/dev/null || true

# Select the Inbox explicitly to start the agent in the right place
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    echo "Initial screenshot captured."
fi

echo "=== Task setup complete ==="