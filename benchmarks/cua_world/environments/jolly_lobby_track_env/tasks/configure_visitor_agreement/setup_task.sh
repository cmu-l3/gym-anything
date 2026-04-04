#!/bin/bash
set -e
echo "=== Setting up visitor agreement configuration task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(date)"

# Remove any pre-existing output from previous task runs
rm -f /home/ga/visitor_agreement_configured.png

# Record initial state of Lobby Track config files for comparison
# We track modification times of common config/data file types in the wine prefix
find /home/ga/.wine/drive_c -iname "*.sdf" -o -iname "*.config" -o -iname "*.xml" -o -iname "*.ini" 2>/dev/null | while read f; do
    stat -c '%Y %n' "$f" 2>/dev/null
done > /tmp/initial_config_state.txt 2>/dev/null || true

# Ensure Lobby Track is running
ensure_lobbytrack_running

# Wait a bit for the app to stabilize
sleep 5

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="