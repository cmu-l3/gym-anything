#!/bin/bash
set -e
echo "=== Setting up Streaming Schema Evolution task ==="

# Source shared utilities if available
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create directories
mkdir -p /home/ga/Documents/databases
mkdir -p /home/ga/Documents/scripts
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents

# Create working copy of Chinook database
CHINOOK_SRC="/home/ga/Documents/databases/chinook.db"
CHINOOK_DEST="/home/ga/Documents/databases/chinook_streaming.db"

# Ensure source exists (download if missing - fallback)
if [ ! -f "$CHINOOK_SRC" ]; then
    echo "Downloading Chinook database..."
    wget -q -O "$CHINOOK_SRC" "https://github.com/lerocha/chinook-database/raw/master/ChinookDatabase/DataSources/Chinook_Sqlite.sqlite" 2>/dev/null || \
    echo "Failed to download Chinook source"
fi

if [ -f "$CHINOOK_SRC" ]; then
    cp "$CHINOOK_SRC" "$CHINOOK_DEST"
    chmod 666 "$CHINOOK_DEST"
    chown ga:ga "$CHINOOK_DEST"
    echo "Created working database: $CHINOOK_DEST"
else
    echo "ERROR: Source database not found!"
    exit 1
fi

# Record initial state for anti-gaming (Table counts)
sqlite3 "$CHINOOK_DEST" "SELECT name FROM sqlite_master WHERE type='table';" | sort > /tmp/initial_tables.txt
sqlite3 "$CHINOOK_DEST" "SELECT COUNT(*) FROM customers;" > /tmp/initial_customer_count.txt
sqlite3 "$CHINOOK_DEST" "PRAGMA table_info(customers);" | wc -l > /tmp/initial_customers_cols.txt
sqlite3 "$CHINOOK_DEST" "PRAGMA table_info(tracks);" | wc -l > /tmp/initial_tracks_cols.txt

# Remove any stale script file
rm -f /home/ga/Documents/scripts/streaming_migration.sql

# Ensure DBeaver is running
if ! pgrep -f "dbeaver" > /dev/null; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "dbeaver"; then
            break
        fi
        sleep 1
    done
fi

# Maximize and focus DBeaver
DISPLAY=:1 wmctrl -r "DBeaver" -b add,maximized_vert,maximized_horz 2>/dev/null || true
WID=$(DISPLAY=:1 wmctrl -l | grep -i "dbeaver" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
fi

# Dismiss any dialogs (common in DBeaver startup)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="