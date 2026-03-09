#!/bin/bash
set -e
echo "=== Setting up keyboard_shortcuts_tile_view task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Remove any prior artifacts
rm -f /home/ga/shortcuts_reference.txt
rm -f /tmp/task_result.json

# Ensure Jitsi Meet is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Start Firefox on the pre-join page for the specific room
ROOM_URL="${JITSI_BASE_URL:-http://localhost:8080}/team-standup-daily"
echo "Opening Firefox at $ROOM_URL"
restart_firefox "$ROOM_URL" 10

# Maximize Firefox to ensure UI elements are visible
maximize_firefox
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Instructions:"
echo "1. Join 'team-standup-daily'"
echo "2. Find keyboard shortcuts help"
echo "3. Write 5 shortcuts to ~/shortcuts_reference.txt"
echo "4. Toggle Tile View using the shortcut"