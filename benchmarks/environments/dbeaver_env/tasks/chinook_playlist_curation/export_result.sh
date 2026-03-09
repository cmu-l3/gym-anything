#!/bin/bash
# Export script for chinook_playlist_curation
# Validates database state against calculated ground truth

echo "=== Exporting Playlist Curation Result ==="

source /workspace/scripts/task_utils.sh

DB_PATH="/home/ga/Documents/databases/chinook.db"
CSV_PATH="/home/ga/Documents/exports/playlist_summary.csv"
SQL_PATH="/home/ga/Documents/scripts/playlist_curation.sql"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check files exist and were modified
CSV_EXISTS="false"
CSV_MODIFIED="false"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -ge "$TASK_START" ]; then CSV_MODIFIED="true"; fi
fi

SQL_EXISTS="false"
SQL_MODIFIED="false"
if [ -f "$SQL_PATH" ]; then
    SQL_EXISTS="true"
    MTIME=$(stat -c %Y "$SQL_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -ge "$TASK_START" ]; then SQL_MODIFIED="true"; fi
fi

# Verify DBeaver connection exists
CONNECTION_EXISTS=$(check_dbeaver_connection "Chinook")

# --- DATABASE VERIFICATION ---
# We verify the actual data in the database matches the ground truth
# The agent is expected to have inserted rows into 'playlists' and 'playlist_track'

echo "Verifying database content..."
python3 -c "
import sqlite3
import json
import os
import csv
import math

db_path = '$DB_PATH'
csv_path = '$CSV_PATH'
gt_file = '/tmp/playlist_ground_truth.json'
result_file = '/tmp/task_result.json'

result = {
    'connection_exists': '$CONNECTION_EXISTS' == 'true',
    'csv_exists': '$CSV_EXISTS' == 'true',
    'csv_modified': '$CSV_MODIFIED' == 'true',
    'sql_exists': '$SQL_EXISTS' == 'true',
    'sql_modified': '$SQL_MODIFIED' == 'true',
    'playlists_created': {},
    'csv_content_valid': False,
    'timestamp': '$(date -Iseconds)'
}

try:
    with open(gt_file, 'r') as f:
        gt = json.load(f)

    conn = sqlite3.connect(db_path)
    c = conn.cursor()

    # Verify each playlist
    targets = {
        'Long Rock Anthems': 'long_rock_anthems',
        'Global Bestsellers': 'global_bestsellers',
        'Hidden Gems': 'hidden_gems'
    }

    for name, key in targets.items():
        # Check if playlist exists
        c.execute('SELECT PlaylistId FROM playlists WHERE Name = ?', (name,))
        row = c.fetchone()
        
        p_res = {
            'exists': False,
            'track_count': 0,
            'track_count_match': False,
            'logic_check_pass': False
        }

        if row:
            p_res['exists'] = True
            pid = row[0]
            
            # Count tracks
            c.execute('SELECT COUNT(*) FROM playlist_track WHERE PlaylistId = ?', (pid,))
            count = c.fetchone()[0]
            p_res['track_count'] = count
            
            expected_count = gt[key]['count']
            p_res['track_count_match'] = (count == expected_count)
            
            # Logic Verification (Specific per playlist)
            if key == 'long_rock_anthems':
                # Verify ALL tracks in this playlist are Rock AND > 5min
                # Count invalid tracks
                c.execute('''
                    SELECT COUNT(*)
                    FROM playlist_track pt
                    JOIN tracks t ON pt.TrackId = t.TrackId
                    JOIN genres g ON t.GenreId = g.GenreId
                    WHERE pt.PlaylistId = ?
                    AND (g.Name != 'Rock' OR t.Milliseconds <= 300000)
                ''', (pid,))
                invalid = c.fetchone()[0]
                p_res['logic_check_pass'] = (invalid == 0 and count > 0)

            elif key == 'hidden_gems':
                # Verify ALL tracks are NOT in invoice_items
                c.execute('''
                    SELECT COUNT(*)
                    FROM playlist_track pt
                    WHERE pt.PlaylistId = ?
                    AND pt.TrackId IN (SELECT DISTINCT TrackId FROM invoice_items)
                ''', (pid,))
                invalid = c.fetchone()[0]
                p_res['logic_check_pass'] = (invalid == 0 and count > 0)

            elif key == 'global_bestsellers':
                # Verify sum of durations matches (proxy for exact track set)
                # Since exact set is unique, duration sum is a good fingerprint
                c.execute('''
                    SELECT SUM(t.Milliseconds)
                    FROM playlist_track pt
                    JOIN tracks t ON pt.TrackId = t.TrackId
                    WHERE pt.PlaylistId = ?
                ''', (pid,))
                dur = c.fetchone()[0] or 0
                expected_dur = gt[key]['duration_ms']
                # Allow tiny difference? No, integers should match.
                p_res['logic_check_pass'] = (abs(dur - expected_dur) < 100)

        result['playlists_created'][key] = p_res

    # Verify CSV Content
    if os.path.exists(csv_path):
        try:
            with open(csv_path, 'r') as f:
                reader = csv.DictReader(f)
                rows = list(reader)
                
                # Check for required columns
                req_cols = ['PlaylistName', 'TrackCount', 'TotalDurationMinutes']
                headers = reader.fieldnames or []
                cols_present = all(c in headers for c in req_cols)
                
                # Check for 3 data rows
                row_count_ok = (len(rows) == 3)
                
                # Check values loosely (within margin of error for duration calculation)
                values_ok = True
                for row in rows:
                    pname = row.get('PlaylistName', '')
                    if pname in targets:
                        key = targets[pname]
                        # Check count
                        try:
                            c_val = int(row.get('TrackCount', 0))
                            if c_val != gt[key]['count']:
                                values_ok = False
                        except:
                            values_ok = False
                
                result['csv_content_valid'] = cols_present and row_count_ok and values_ok
        except:
            result['csv_content_valid'] = False

    conn.close()

except Exception as e:
    result['error'] = str(e)

with open(result_file, 'w') as f:
    json.dump(result, f, indent=2)
"

# Permission safety
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="