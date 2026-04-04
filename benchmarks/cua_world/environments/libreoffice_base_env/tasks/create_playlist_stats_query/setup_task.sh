#!/bin/bash
set -e
echo "=== Setting up create_playlist_stats_query task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Setup LibreOffice Base (Kill existing, Restore ODB, Launch, Wait, Dismiss Dialogs)
setup_libreoffice_base_task /home/ga/chinook.odb

# 3. Record initial ODB state
INITIAL_SIZE=$(stat -c%s /home/ga/chinook.odb 2>/dev/null || echo "0")
echo "$INITIAL_SIZE" > /tmp/initial_odb_size.txt

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="