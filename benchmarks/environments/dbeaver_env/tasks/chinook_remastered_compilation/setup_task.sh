#!/bin/bash
set -e
echo "=== Setting up Chinook Remastered Compilation Task ==="

source /workspace/scripts/task_utils.sh

DB_PATH="/home/ga/Documents/databases/chinook.db"
HIDDEN_GT="/root/.ground_truth_top10.json"

# Ensure DBeaver is running (standard setup)
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "dbeaver"; then
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize DBeaver
focus_dbeaver
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# ------------------------------------------------------------------
# DATA PREPARATION: Inject deterministic sales data
# ------------------------------------------------------------------
echo "Injecting sales data for Iron Maiden..."

# 1. Create a dummy invoice for our injections
sqlite3 "$DB_PATH" "INSERT OR IGNORE INTO invoices (InvoiceId, CustomerId, InvoiceDate, Total) VALUES (9999, 1, '2025-01-01', 100);"

# 2. Get 15 Iron Maiden Track IDs (ArtistId 90 -> Albums -> Tracks)
# We limit to 15 so we have some that WON'T make the cut (we only want top 10)
TRACK_IDS=$(sqlite3 "$DB_PATH" "
    SELECT t.TrackId 
    FROM tracks t 
    JOIN albums a ON t.AlbumId = a.AlbumId 
    WHERE a.ArtistId = 90 
    ORDER BY t.TrackId 
    LIMIT 15;")

# 3. Insert sales to force a specific ranking
# We give the first track 20 sales, next 19, etc.
count=20
for tid in $TRACK_IDS; do
    # Insert 'count' items for this track
    sqlite3 "$DB_PATH" "INSERT INTO invoice_items (InvoiceId, TrackId, UnitPrice, Quantity) VALUES (9999, $tid, 0.99, $count);"
    count=$((count - 1))
done

echo "Sales data injected."

# ------------------------------------------------------------------
# GROUND TRUTH GENERATION
# ------------------------------------------------------------------
# Calculate the expected Top 10 based on the data we just injected
# We store (Milliseconds, Bytes) pairs because TrackIds will change in the new album,
# but physical characteristics of the song should remain identical.
echo "Calculating ground truth..."

python3 << PYEOF
import sqlite3
import json

conn = sqlite3.connect('$DB_PATH')
c = conn.cursor()

query = """
    SELECT t.TrackId, t.Name, t.Milliseconds, t.Bytes, SUM(ii.Quantity) as TotalSold
    FROM tracks t
    JOIN invoice_items ii ON t.TrackId = ii.TrackId
    JOIN albums a ON t.AlbumId = a.AlbumId
    WHERE a.ArtistId = 90
    GROUP BY t.TrackId
    ORDER BY TotalSold DESC, t.Name ASC
    LIMIT 10
"""

rows = c.execute(query).fetchall()
ground_truth = []
for r in rows:
    ground_truth.append({
        "original_id": r[0],
        "name": r[1],
        "ms": r[2],
        "bytes": r[3],
        "sales": r[4]
    })

with open('$HIDDEN_GT', 'w') as f:
    json.dump(ground_truth, f)

print(f"Ground truth saved with {len(ground_truth)} tracks.")
PYEOF

# Record task start time
date +%s > /tmp/task_start_time.txt

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="