#!/bin/bash
echo "=== Setting up queue_offline_email task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

TB_PROFILE="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="${TB_PROFILE}/Mail/Local Folders"

# Ensure Unsent Messages file exists so we can baseline it
touch "${LOCAL_MAIL_DIR}/Unsent Messages"
chown ga:ga "${LOCAL_MAIL_DIR}/Unsent Messages"

# Record initial counts
INITIAL_UNSENT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/Unsent Messages" 2>/dev/null || echo "0")
echo "$INITIAL_UNSENT" > /tmp/initial_unsent_count.txt

# Ensure Thunderbird is online at the start
if [ -f "${TB_PROFILE}/prefs.js" ]; then
    sed -i 's/user_pref("network.online", false);/user_pref("network.online", true);/g' "${TB_PROFILE}/prefs.js"
fi

# Start Thunderbird if not running
if ! pgrep -f "thunderbird" > /dev/null; then
    su - ga -c "DISPLAY=:1 thunderbird -profile ${TB_PROFILE} &"
    sleep 8
fi

# Wait for Thunderbird window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Mozilla Thunderbird"; then
        break
    fi
    sleep 1
done

# Focus and Maximize the window
WID=$(DISPLAY=:1 xdotool search --name "Mozilla Thunderbird" | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Dismiss any stray dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="