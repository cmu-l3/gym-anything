#!/bin/bash
set -e
echo "=== Setting up configure_checkin_fields task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
record_start_time "configure_checkin_fields"

# Ensure Lobby Track is running
ensure_lobbytrack_running

# Wait a moment for stability
sleep 5

# Ensure window is maximized and focused
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "lobby\|jolly\|visitor\|track" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Dismiss any popup dialogs that might block the view
dismiss_startup_dialogs

# Record initial state of config/database files (to detect saving later)
# Lobby Track typically uses .sdf (SQL CE), .xml, or .config files in ProgramData or AppData
echo "Snapshotting configuration file timestamps..."
LOBBYTRACK_DIRS=(
    "/home/ga/.wine/drive_c/ProgramData/Jolly Technologies"
    "/home/ga/.wine/drive_c/users/ga/Application Data/Jolly Technologies"
    "/home/ga/.wine/drive_c/Program Files/Jolly Technologies"
)

rm -f /tmp/config_files_before.txt
touch /tmp/config_files_before.txt

for dir in "${LOBBYTRACK_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        find "$dir" -type f \( -iname "*.config" -o -iname "*.xml" -o -iname "*.sdf" -o -iname "*.ini" \) -exec stat --format='%n %Y %s' {} \; >> /tmp/config_files_before.txt 2>/dev/null || true
    fi
done

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="