#!/bin/bash
set -e
echo "=== Setting up adjust_badge_print_size task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (critical for checking file modification timestamps)
date +%s > /tmp/task_start_time.txt
echo "Task started at: $(cat /tmp/task_start_time.txt)"

# Ensure Lobby Track is running
ensure_lobbytrack_running

# Wait for window to be fully ready
sleep 5

# Ensure window is maximized for best VLM visibility
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "lobby\|jolly\|visitor\|track" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    echo "Maximizing window $WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Dismiss any potential startup dialogs/popups
dismiss_startup_dialogs

# Snapshot initial state of config files (to compare later)
# We look for XML or config files that might store these settings
echo "Snapshotting initial config state..."
mkdir -p /tmp/initial_configs
find /home/ga/.wine/drive_c -iname "*.xml" -o -iname "*.config" -o -iname "*.ini" 2>/dev/null | head -n 200 > /tmp/config_file_list.txt

while read -r file; do
    # Create a hash of the file content
    md5sum "$file" >> /tmp/initial_configs/file_hashes.txt 2>/dev/null || true
done < /tmp/config_file_list.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="