#!/bin/bash
# Setup script for chinook_test_subset task

set -e
echo "=== Setting up Chinook Test Subset Task ==="

source /workspace/scripts/task_utils.sh

# Paths
SOURCE_DB="/home/ga/Documents/databases/chinook.db"
TARGET_DB="/home/ga/Documents/databases/chinook_brazil_test.db"
SCRIPT_PATH="/home/ga/Documents/scripts/brazil_subset_extraction.sql"

# 1. Ensure clean state
echo "Cleaning up previous run artifacts..."
rm -f "$TARGET_DB"
rm -f "$SCRIPT_PATH"
# Also remove any journal files that might exist
rm -f "${TARGET_DB}-journal" "${TARGET_DB}-wal" "${TARGET_DB}-shm"

# 2. Ensure source database exists
if [ ! -f "$SOURCE_DB" ]; then
    echo "Source database not found at $SOURCE_DB. Attempting to restore..."
    # The environment setup should have handled this, but self-healing is good
    /workspace/scripts/setup_dbeaver.sh
fi

# 3. Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Start DBeaver
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    
    # Wait for it to start
    for i in {1..30}; do
        if is_dbeaver_running; then
            echo "DBeaver started."
            break
        fi
        sleep 1
    done
fi

# 5. Configure window
focus_dbeaver
sleep 2
# Maximize using wmctrl
DISPLAY=:1 wmctrl -r "DBeaver" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="