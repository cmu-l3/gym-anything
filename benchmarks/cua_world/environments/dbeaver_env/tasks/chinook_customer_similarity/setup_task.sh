#!/bin/bash
# Setup script for chinook_customer_similarity task
# Generates ground truth data and ensures clean environment

set -e
echo "=== Setting up Chinook Customer Similarity Task ==="

source /workspace/scripts/task_utils.sh

# Paths
DB_PATH="/home/ga/Documents/databases/chinook.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents/

# Clean up any previous runs
rm -f "$EXPORT_DIR/customer_similarity.csv"
rm -f "$SCRIPTS_DIR/similarity_query.sql"
rm -f /tmp/chinook_ground_truth.json

# Ensure DBeaver is running
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
fi

# Focus DBeaver
focus_dbeaver

# Generate Ground Truth using Python + SQLite
# This runs the logic directly on the DB to calculate the expected top 20
echo "Generating ground truth data..."
python3 << 'PYEOF'
import sqlite3
import json
import os

db_path = "/home/ga/Documents/databases/chinook.db"
output_path = "/tmp/chinook_ground_truth.json"

if not os.path.exists(db_path):
    print(f"Error: Database not found at {db_path}")
    exit(1)

conn = sqlite3.connect(db_path)
c = conn.cursor()

# Query to calculate Jaccard Similarity
# Logic:
# 1. Get distinct artists per customer
# 2. Self-join to find pairs sharing artists
# 3. Calculate metrics
query = """
WITH customer_artists AS (
    SELECT DISTINCT c.CustomerId, c.FirstName, c.LastName, ar.ArtistId
    FROM customers c
    JOIN invoices i ON c.CustomerId = i.CustomerId
    JOIN invoice_items ii ON i.InvoiceId = ii.InvoiceId
    JOIN tracks t ON ii.TrackId = t.TrackId
    JOIN albums al ON t.AlbumId = al.AlbumId
    JOIN artists ar ON al.ArtistId = ar.ArtistId
),
artist_counts AS (
    SELECT CustomerId, FirstName, LastName, COUNT(*) as ArtistCount
    FROM customer_artists
    GROUP BY CustomerId, FirstName, LastName
),
shared_counts AS (
    SELECT 
        t1.CustomerId as CA, 
        t2.CustomerId as CB, 
        COUNT(*) as Shared
    FROM customer_artists t1
    JOIN customer_artists t2 ON t1.ArtistId = t2.ArtistId AND t1.CustomerId < t2.CustomerId
    GROUP BY t1.CustomerId, t2.CustomerId
)
SELECT 
    s.CA, 
    s.CB, 
    ac1.FirstName || ' ' || ac1.LastName as NameA,
    ac2.FirstName || ' ' || ac2.LastName as NameB,
    s.Shared,
    (ac1.ArtistCount + ac2.ArtistCount - s.Shared) as TotalUnion,
    ROUND(CAST(s.Shared AS REAL) / (ac1.ArtistCount + ac2.ArtistCount - s.Shared), 4) as Jaccard
FROM shared_counts s
JOIN artist_counts ac1 ON s.CA = ac1.CustomerId
JOIN artist_counts ac2 ON s.CB = ac2.CustomerId
ORDER BY Jaccard DESC, s.Shared DESC
LIMIT 20;
"""

try:
    c.execute(query)
    rows = c.fetchall()
    
    result = []
    for r in rows:
        result.append({
            "CustomerIdA": r[0],
            "CustomerIdB": r[1],
            "CustomerNameA": r[2],
            "CustomerNameB": r[3],
            "SharedArtists": r[4],
            "TotalArtists": r[5],
            "JaccardSimilarity": r[6]
        })
    
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)
    
    print(f"Ground truth generated with {len(result)} rows.")

except Exception as e:
    print(f"Error generating ground truth: {e}")
    exit(1)
finally:
    conn.close()
PYEOF

# Record task start time
date +%s > /tmp/task_start_time.txt

# Initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Setup Complete ==="