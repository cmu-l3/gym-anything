#!/bin/bash
# Setup script for chinook_album_completeness task
# Calculates ground truth values and sets up the environment

set -e
echo "=== Setting up Chinook Album Completeness Task ==="

source /workspace/scripts/task_utils.sh

# Database and paths
DB_PATH="/home/ga/Documents/databases/chinook.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist and are clean
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR"
rm -f "$EXPORT_DIR/album_sales_analysis.csv"
rm -f "$SCRIPTS_DIR/album_analysis.sql"
rm -f /tmp/task_result.json

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure DBeaver is running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

# Focus DBeaver
focus_dbeaver

# ------------------------------------------------------------------
# CALCULATE GROUND TRUTH
# We execute the "perfect" query using sqlite3 to get the exact values
# expected for verification. This handles any potential DB updates.
# ------------------------------------------------------------------
echo "Calculating ground truth..."

GROUND_TRUTH_SQL="
WITH AlbumSizes AS (
    SELECT AlbumId, COUNT(TrackId) as TotalTracks
    FROM Tracks
    GROUP BY AlbumId
),
InvoicePurchases AS (
    SELECT 
        ii.InvoiceId,
        t.AlbumId,
        COUNT(DISTINCT ii.TrackId) as PurchasedTracks,
        SUM(ii.UnitPrice * ii.Quantity) as PurchaseValue
    FROM InvoiceItems ii
    JOIN Tracks t ON ii.TrackId = t.TrackId
    GROUP BY ii.InvoiceId, t.AlbumId
)
SELECT 
    CASE 
        WHEN ip.PurchasedTracks = asz.TotalTracks THEN 'Full Album' 
        ELSE 'Single/Partial' 
    END as PurchaseType,
    ROUND(SUM(ip.PurchaseValue), 2) as TotalRevenue,
    COUNT(*) as TransactionCount
FROM InvoicePurchases ip
JOIN AlbumSizes asz ON ip.AlbumId = asz.AlbumId
GROUP BY 1
ORDER BY 1;
"

# Execute query and parse into JSON
# Output format from sqlite3 -separator '|' will be:
# Full Album|123.45|10
# Single/Partial|456.78|50

sqlite3 -separator '|' "$DB_PATH" "$GROUND_TRUTH_SQL" > /tmp/ground_truth_raw.txt

# Python script to convert raw text to JSON
python3 << PYEOF
import json
import sys

data = {}
try:
    with open('/tmp/ground_truth_raw.txt', 'r') as f:
        for line in f:
            parts = line.strip().split('|')
            if len(parts) == 3:
                ptype = parts[0]
                rev = float(parts[1])
                count = int(parts[2])
                data[ptype] = {"TotalRevenue": rev, "TransactionCount": count}
    
    with open('/tmp/ground_truth.json', 'w') as out:
        json.dump(data, out, indent=2)
    print("Ground truth saved successfully.")
except Exception as e:
    print(f"Error processing ground truth: {e}")
PYEOF

echo "Ground Truth Data:"
cat /tmp/ground_truth.json

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task Setup Complete ==="