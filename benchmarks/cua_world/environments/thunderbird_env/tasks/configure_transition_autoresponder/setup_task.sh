#!/bin/bash
echo "=== Setting up Configure Transition Autoresponder Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Find the Thunderbird profile directory
PROFILE_DIR=$(find /home/ga/.thunderbird -maxdepth 1 -type d -name "*default*" | head -n 1)

if [ -n "$PROFILE_DIR" ]; then
    LOCAL_MAIL_DIR="$PROFILE_DIR/Mail/Local Folders"
    mkdir -p "$LOCAL_MAIL_DIR"

    # Inject a realistic background email to make the scenario tangible
    INBOX_MBOX="$LOCAL_MAIL_DIR/Inbox"
    if [ -f "$INBOX_MBOX" ]; then
        echo -e "From client@megacorp.com Mon Jan 01 12:00:00 2024\r\nFrom: client@megacorp.com\r\nTo: ga@example.com\r\nSubject: MegaCorp Project Update\r\nDate: Mon, 1 Jan 2024 12:00:00 +0000\r\n\r\nHi,\n\nJust checking in on the latest deliverables for the MegaCorp engagement.\n\nBest,\nClient\r\n" >> "$INBOX_MBOX"
    fi

    # Clean up any existing state that matches the task (ensure clean slate)
    rm -f "$LOCAL_MAIL_DIR/MegaCorp Archive" 2>/dev/null || true
    rm -f "$LOCAL_MAIL_DIR/MegaCorp Archive.msf" 2>/dev/null || true
    
    # Remove existing filters to prevent passing without doing work
    rm -f "$PROFILE_DIR/msgFilterRules.dat" 2>/dev/null || true
fi

# Ensure Thunderbird is running
if ! pgrep -f "thunderbird" > /dev/null; then
    echo "Starting Thunderbird..."
    su - ga -c "DISPLAY=:1 thunderbird &"
    
    # Wait for window to appear
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Mozilla Thunderbird"; then
            break
        fi
        sleep 1
    done
    sleep 3 # Extra time for UI to stabilize
fi

# Maximize the window (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r "Mozilla Thunderbird" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Thunderbird" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="