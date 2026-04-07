#!/bin/bash
set -euo pipefail

echo "=== Setting up Configure Disk Space Management Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

PROFILE_DIR="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="${PROFILE_DIR}/Mail/Local Folders"

# Wait for Thunderbird to be ready or start it
if ! is_thunderbird_running; then
    start_thunderbird
fi

wait_for_thunderbird_window 30

# Inject ~20 emails into the Trash folder so the agent has something to empty
echo "Populating Trash folder with emails..."
mkdir -p "$LOCAL_MAIL_DIR"
TRASH_FILE="${LOCAL_MAIL_DIR}/Trash"

# Clear existing trash if any
> "$TRASH_FILE"

SPAM_COUNT=0
if [ -d "/workspace/assets/emails/spam" ]; then
    for eml_file in /workspace/assets/emails/spam/*; do
        if [ -f "$eml_file" ] && [ $SPAM_COUNT -lt 20 ]; then
            SENDER=$(grep -m1 "^From:" "$eml_file" 2>/dev/null | sed 's/From: //' | head -1 || echo "spammer@example.com")
            DATE=$(grep -m1 "^Date:" "$eml_file" 2>/dev/null | sed 's/Date: //' | head -1 || echo "Mon Jan 01 00:00:00 2024")

            echo "From ${SENDER} ${DATE}" >> "$TRASH_FILE"
            cat "$eml_file" >> "$TRASH_FILE"
            echo "" >> "$TRASH_FILE"

            SPAM_COUNT=$((SPAM_COUNT + 1))
        fi
    done
fi

chown -R ga:ga "$PROFILE_DIR"

# Click center of desktop to focus it
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Thunderbird window and maximize
echo "Focusing Thunderbird window..."
wid=$(get_thunderbird_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Ensure any existing settings tabs are closed by returning to main tab
# (Ctrl+1 usually switches to the first tab, the Mail view)
su - ga -c "DISPLAY=:1 xdotool key ctrl+1" || true
sleep 1

# Record initial count for Trash
INITIAL_TRASH_COUNT=$(count_emails_in_mbox "$TRASH_FILE")
echo "$INITIAL_TRASH_COUNT" > /tmp/initial_trash_count.txt
echo "Initial Trash count: $INITIAL_TRASH_COUNT"

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="