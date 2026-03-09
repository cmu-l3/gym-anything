#!/bin/bash
echo "=== Setting up purge_obsolete_inventory task ==="

source /workspace/scripts/task_utils.sh

# 1. Generate Ground Truth
# We use the source SQLite file to determine exactly which tracks are unsold.
# This ensures our verifier has the exact expected IDs.
echo "Generating ground truth data..."

python3 -c "
import sqlite3
import json
import os

conn = sqlite3.connect('/opt/libreoffice_base_samples/Chinook_Sqlite.sqlite')
cursor = conn.cursor()

# Find tracks not in InvoiceLine
cursor.execute('''
    SELECT t.TrackId, t.Name, t.Composer, t.UnitPrice
    FROM Track t
    LEFT JOIN InvoiceLine il ON t.TrackId = il.TrackId
    WHERE il.InvoiceLineId IS NULL
    ORDER BY t.TrackId
''')

rows = cursor.fetchall()
unsold_tracks = []
for r in rows:
    unsold_tracks.append({
        'TrackId': r[0],
        'Name': r[1],
        'Composer': r[2],
        'UnitPrice': r[3]
    })

print(f'Found {len(unsold_tracks)} unsold tracks.')

with open('/tmp/ground_truth_unsold.json', 'w') as f:
    json.dump(unsold_tracks, f, indent=2)

# Also count total tracks for verification
cursor.execute('SELECT COUNT(*) FROM Track')
total_tracks = cursor.fetchone()[0]
with open('/tmp/ground_truth_counts.json', 'w') as f:
    json.dump({'total_tracks_initial': total_tracks, 'unsold_count': len(unsold_tracks)}, f)

conn.close()
"

# 2. Standard LO Base Setup
# Kill existing, restore fresh ODB, launch, wait, maximize
setup_libreoffice_base_task /home/ga/chinook.odb

# 3. Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Task setup complete ==="