#!/bin/bash
set -euo pipefail

echo "=== Setting up Export Visitor Log Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming timestamp verification)
record_start_time "export_visitor_log"

# 2. Prepare the environment
# Ensure Desktop directory exists for the export
mkdir -p /home/ga/Desktop
# Remove any previous attempts/stale files to ensure clean state
rm -f /home/ga/Desktop/visitor_audit_export.*

# 3. Ensure Lobby Track is running and in a clean state
echo "Ensuring Lobby Track is running..."
ensure_lobbytrack_running
sleep 5

# 4. Verify/Inject Data
# Note: In a real scenario, we would inject SQL directly. 
# Since Lobby Track uses a compact file DB, we rely on the environment's pre-loaded data 
# or use UI automation to add a marker record if needed. 
# Here we assume the standard environment data set is present.
# We will create a marker file to indicate setup is done.
touch /tmp/setup_complete.txt

# 5. Bring window to front and maximize
echo "Focusing application..."
WID=$(wait_for_lobbytrack_window 10)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 6. Take initial screenshot for evidence
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="