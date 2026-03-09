#!/bin/bash
# Setup script for chinook_playlist_curation task
# Ensures clean state and calculates ground truth

set -e
echo "=== Setting up Chinook Playlist Curation Task ==="

source /workspace/scripts/task_utils.sh

DB_PATH="/home/ga/Documents/databases/chinook.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents/

# Ensure DBeaver is running
if [ "$(is_dbeaver_running)" = "false" ]; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

# Focus DBeaver
focus_dbeaver

# Clean up any previous run artifacts
rm -f "$EXPORT_DIR/playlist_summary.csv"
rm -f "$SCRIPTS_DIR/playlist_curation.sql"

# Clean Database State: Remove the specific playlists if they already exist
# This ensures the agent must create them fresh
echo "Cleaning database state..."
sqlite3 "$DB_PATH" <<EOF
DELETE FROM playlist_track WHERE PlaylistId IN (SELECT PlaylistId FROM playlists WHERE Name IN ('Long Rock Anthems', 'Global Bestsellers', 'Hidden Gems'));
DELETE FROM playlists WHERE Name IN ('Long Rock Anthems', 'Global Bestsellers', 'Hidden Gems');
EOF

# Record initial counts for anti-gaming verification
INITIAL_PLAYLIST_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM playlists;")
INITIAL_PT_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM playlist_track;")

echo "$INITIAL_PLAYLIST_COUNT" > /tmp/initial_playlist_count
echo "$INITIAL_PT_COUNT" > /tmp/initial_pt_count
date +%s > /tmp/task_start_time

# Calculate Ground Truths using Python to handle the complex logic (especially tie-breaking)
# We save these expectations to a hidden file to compare against later
echo "Calculating ground truth..."
python3 -c "
import sqlite3
import json

conn = sqlite3.connect('$DB_PATH')
c = conn.cursor()

# 1. Long Rock Anthems Truth
c.execute('''
    SELECT COUNT(*), SUM(t.Milliseconds)
    FROM tracks t
    JOIN genres g ON t.GenreId = g.GenreId
    WHERE g.Name = 'Rock' AND t.Milliseconds > 300000
''')
rock_row = c.fetchone()
rock_count = rock_row[0]
rock_duration = rock_row[1]

# 2. Hidden Gems Truth
c.execute('''
    SELECT COUNT(*), SUM(Milliseconds)
    FROM tracks
    WHERE TrackId NOT IN (SELECT DISTINCT TrackId FROM invoice_items)
''')
hidden_row = c.fetchone()
hidden_count = hidden_row[0]
hidden_duration = hidden_row[1]

# 3. Global Bestsellers Truth (Complex Logic)
# Logic: For each country, sum quantity per track, order by sum desc, trackid asc, take top 1
c.execute('''
    SELECT BillingCountry, i.TrackId, SUM(Quantity) as TotalQty
    FROM invoices inv
    JOIN invoice_items i ON inv.InvoiceId = i.InvoiceId
    GROUP BY BillingCountry, i.TrackId
''')
all_sales = c.fetchall()

# Process in python for precise tie-breaking matching agent instructions
# Map: Country -> (TrackId, Qty)
best_sellers = {}
for country, track_id, qty in all_sales:
    if country not in best_sellers:
        best_sellers[country] = (track_id, qty)
    else:
        current_best_id, current_best_qty = best_sellers[country]
        # Check if this track is better
        if qty > current_best_qty:
            best_sellers[country] = (track_id, qty)
        elif qty == current_best_qty:
            # Tiebreaker: lowest TrackId
            if track_id < current_best_id:
                best_sellers[country] = (track_id, qty)

global_count = len(best_sellers)
# Calculate total duration for these specific tracks
global_track_ids = [str(x[0]) for x in best_sellers.values()]
if global_track_ids:
    id_list = ','.join(global_track_ids)
    c.execute(f'SELECT SUM(Milliseconds) FROM tracks WHERE TrackId IN ({id_list})')
    global_duration = c.fetchone()[0]
else:
    global_duration = 0

truth = {
    'long_rock_anthems': {'count': rock_count, 'duration_ms': rock_duration},
    'hidden_gems': {'count': hidden_count, 'duration_ms': hidden_duration},
    'global_bestsellers': {'count': global_count, 'duration_ms': global_duration}
}

with open('/tmp/playlist_ground_truth.json', 'w') as f:
    json.dump(truth, f)

print(f'Ground Truth Calculated: {json.dumps(truth)}')
conn.close()
"

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="