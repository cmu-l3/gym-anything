#!/bin/bash
echo "=== Setting up Chinook ABC Classification Task ==="

source /workspace/scripts/task_utils.sh

DB_PATH="/home/ga/Documents/databases/chinook.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure clean state
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR"
rm -f "$EXPORT_DIR/abc_classification.csv"
rm -f "$EXPORT_DIR/abc_summary.csv"
rm -f "$SCRIPTS_DIR/abc_analysis.sql"

# Check DB existence
if [ ! -f "$DB_PATH" ]; then
    echo "ERROR: Chinook database not found at $DB_PATH"
    # Attempt to restore from backup or download if missing (handled by env setup usually, but safety check)
    exit 1
fi

# Drop the target table if it exists (from previous runs) to ensure fresh creation
sqlite3 "$DB_PATH" "DROP TABLE IF EXISTS track_abc_classification;"
echo "Cleaned up database state."

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure DBeaver is running and focused
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 15
fi

focus_dbeaver
maximize_window "DBeaver"

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="