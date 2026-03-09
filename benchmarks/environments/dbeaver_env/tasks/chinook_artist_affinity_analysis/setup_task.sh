#!/bin/bash
# Setup script for chinook_artist_affinity_analysis
# Prepares clean state and generates ground truth data for verification

set -e
echo "=== Setting up Artist Affinity Analysis Task ==="

source /workspace/scripts/task_utils.sh

# Paths
DB_PATH="/home/ga/Documents/databases/chinook.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# 1. Clean up previous artifacts
rm -f "$EXPORT_DIR/artist_affinity_pairs.csv"
rm -f "$SCRIPTS_DIR/affinity_query.sql"
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents

# 2. Verify Database Exists
if [ ! -f "$DB_PATH" ]; then
    echo "ERROR: Chinook database not found at $DB_PATH"
    # Attempt to copy from standard location if setup_dbeaver.sh put it there
    if [ -f "/workspace/data/chinook.db" ]; then
        cp /workspace/data/chinook.db "$DB_PATH"
    else
        echo "CRITICAL: Cannot find chinook.db"
        exit 1
    fi
fi

# 3. Generate Ground Truth (Hidden from agent)
# We calculate the top 20 affinity pairs using Python/SQLite to compare against user output later
echo "Generating ground truth data..."
python3 << 'PYEOF'
import sqlite3
import json
import os

db_path = "/home/ga/Documents/databases/chinook.db"
output_path = "/tmp/affinity_ground_truth.json"

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Ground Truth Query
    # Logic: Self-join invoice_items via InvoiceId to find pairs of tracks, 
    # then join up to Artists. Filter for A.Name < B.Name to deduplicate pairs.
    query = """
    SELECT 
        a1.Name as Artist_A, 
        a2.Name as Artist_B, 
        COUNT(*) as CoOccurrenceCount
    FROM invoice_items ii1
    JOIN invoice_items ii2 ON ii1.InvoiceId = ii2.InvoiceId
    JOIN tracks t1 ON ii1.TrackId = t1.TrackId
    JOIN tracks t2 ON ii2.TrackId = t2.TrackId
    JOIN albums al1 ON t1.AlbumId = al1.AlbumId
    JOIN albums al2 ON t2.AlbumId = al2.AlbumId
    JOIN artists a1 ON al1.ArtistId = a1.ArtistId
    JOIN artists a2 ON al2.ArtistId = a2.ArtistId
    WHERE a1.Name < a2.Name
    GROUP BY a1.Name, a2.Name
    ORDER BY CoOccurrenceCount DESC, a1.Name ASC
    LIMIT 20;
    """
    
    cursor.execute(query)
    rows = cursor.fetchall()
    
    ground_truth = {
        "top_pairs": [
            {"Artist_A": r[0], "Artist_B": r[1], "Count": r[2]} 
            for r in rows
        ],
        "total_rows_check": len(rows)
    }
    
    with open(output_path, 'w') as f:
        json.dump(ground_truth, f, indent=2)
        
    print(f"Ground truth generated with {len(rows)} pairs.")
    conn.close()

except Exception as e:
    print(f"Error generating ground truth: {e}")
PYEOF

# 4. Record task start state
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_dbeaver_conn_count # Placeholder, we check actual config in export

# 5. Ensure DBeaver is running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

# 6. Setup Window
focus_dbeaver
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="