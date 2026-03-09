#!/bin/bash
# Setup script for chinook_inventory_lifecycle_management
# Prepares the database and records the ground truth for 2013 sales

set -e
echo "=== Setting up Chinook Inventory Lifecycle Task ==="

source /workspace/scripts/task_utils.sh

DB_PATH="/home/ga/Documents/databases/chinook.db"
EXPORT_DIR="/home/ga/Documents/exports"

# Ensure clean state
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/archival_summary.csv"

# Ensure DB exists (setup_dbeaver.sh should have placed it, but we verify/reset)
if [ ! -f "$DB_PATH" ]; then
    echo "Restoring Chinook database..."
    cp /workspace/data/chinook.db "$DB_PATH" 2>/dev/null || \
    wget -q -O "$DB_PATH" "https://github.com/lerocha/chinook-database/raw/master/ChinookDatabase/DataSources/Chinook_Sqlite.sqlite"
fi

# Reset permissions
chown ga:ga "$DB_PATH"
chmod 644 "$DB_PATH"

# CLEANUP: Ensure 'IsArchived' column does not exist from a previous run
# SQLite doesn't support DROP COLUMN easily in older versions, so we rely on fresh DB copy usually.
# But just in case, we check. If it exists, we force a reload.
COLUMN_CHECK=$(sqlite3 "$DB_PATH" "PRAGMA table_info(tracks);" | grep -i "IsArchived" || echo "")
if [ -n "$COLUMN_CHECK" ]; then
    echo "Detected existing IsArchived column. Resetting database..."
    rm -f "$DB_PATH"
    cp /workspace/data/chinook.db "$DB_PATH" 2>/dev/null || \
    wget -q -O "$DB_PATH" "https://github.com/lerocha/chinook-database/raw/master/ChinookDatabase/DataSources/Chinook_Sqlite.sqlite"
    chown ga:ga "$DB_PATH"
fi

# PRE-CALCULATE GROUND TRUTH
# We identify how many tracks SHOULD be archived (not sold in 2013)
# logic: Total Tracks - Tracks Sold in 2013

echo "Calculating ground truth..."
python3 << 'PYEOF'
import sqlite3
import json

db_path = "/home/ga/Documents/databases/chinook.db"
conn = sqlite3.connect(db_path)
c = conn.cursor()

# Get total tracks
c.execute("SELECT COUNT(*) FROM tracks")
total_tracks = c.fetchone()[0]

# Get tracks sold in 2013
# SQLite date string comparison: BETWEEN '2013-01-01' AND '2013-12-31'
query_sold = """
    SELECT COUNT(DISTINCT t.TrackId)
    FROM tracks t
    JOIN invoice_items ii ON t.TrackId = ii.TrackId
    JOIN invoices i ON ii.InvoiceId = i.InvoiceId
    WHERE i.InvoiceDate LIKE '2013-%'
"""
c.execute(query_sold)
sold_count = c.fetchone()[0]

should_be_archived = total_tracks - sold_count

ground_truth = {
    "total_tracks": total_tracks,
    "sold_2013_count": sold_count,
    "should_be_archived_count": should_be_archived
}

print(f"Ground Truth: {ground_truth}")

with open('/tmp/lifecycle_ground_truth.json', 'w') as f:
    json.dump(ground_truth, f)
PYEOF

# Start DBeaver if not running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 dbeaver &" > /dev/null 2>&1 &
    sleep 10
fi

# Focus DBeaver
focus_dbeaver || true
maximize_window "DBeaver" || true

# Record start time
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="