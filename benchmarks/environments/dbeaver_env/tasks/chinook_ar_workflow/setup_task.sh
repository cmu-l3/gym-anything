#!/bin/bash
echo "=== Setting up Chinook AR Workflow Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Define paths
DB_PATH="/home/ga/Documents/databases/chinook.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist and permissions are correct
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents

# Reset database to clean state (remove any previous modifications)
if [ -f "/workspace/data/chinook.db" ]; then
    cp /workspace/data/chinook.db "$DB_PATH"
else
    # Fallback download if not in workspace
    wget -q -O "$DB_PATH" "https://github.com/lerocha/chinook-database/raw/master/ChinookDatabase/DataSources/Chinook_Sqlite.sqlite" 2>/dev/null
fi
chmod 666 "$DB_PATH"
chown ga:ga "$DB_PATH"

# Remove any previous artifacts
rm -f "$EXPORT_DIR/ar_aging_report.csv"
rm -f "$SCRIPTS_DIR/ar_setup.sql"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Record initial file hash to detect if DB was actually modified later
md5sum "$DB_PATH" | awk '{print $1}' > /tmp/initial_db_hash.txt

# Start DBeaver if not running
if ! pgrep -f "dbeaver" > /dev/null; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "dbeaver"; then
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize DBeaver
DISPLAY=:1 wmctrl -r "DBeaver" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "DBeaver" 2>/dev/null || true

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="