#!/bin/bash
set -e
echo "=== Setting up import_csv_to_table task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Kill existing LO instances and restore clean ODB
setup_libreoffice_base_task /home/ga/chinook.odb

# 2. Generate Real CSV Data from SQLite Source
# We use the raw SQLite file to generate the CSV to ensure data consistency
echo "Generating CSV data..."
mkdir -p /home/ga/Documents

SQLITE_DB="/opt/libreoffice_base_samples/Chinook_Sqlite.sqlite"
CSV_PATH="/home/ga/Documents/rock_long_tracks.csv"

# Query: Rock tracks > 5 minutes
QUERY="SELECT t.Name as TrackName, a.Title as AlbumTitle, ar.Name as ArtistName, g.Name as Genre, t.Milliseconds as DurationMs, t.UnitPrice 
FROM Track t 
JOIN Album a ON t.AlbumId = a.AlbumId 
JOIN Artist ar ON a.ArtistId = ar.ArtistId 
JOIN Genre g ON t.GenreId = g.GenreId 
WHERE g.Name = 'Rock' AND t.Milliseconds > 300000 
ORDER BY t.Milliseconds DESC;"

# Use python to export to CSV to handle quoting/escaping correctly
python3 -c "
import sqlite3
import csv
import sys

conn = sqlite3.connect('$SQLITE_DB')
cursor = conn.cursor()
cursor.execute(\"\"\"$QUERY\"\"\")

with open('$CSV_PATH', 'w', newline='', encoding='utf-8') as f:
    writer = csv.writer(f)
    # Write headers
    headers = [description[0] for description in cursor.description]
    writer.writerow(headers)
    # Write rows
    rows = cursor.fetchall()
    writer.writerows(rows)
    print(f'Wrote {len(rows)} rows to CSV')
    
    # Save expected count for verification
    with open('/tmp/expected_row_count.txt', 'w') as count_file:
        count_file.write(str(len(rows)))
"

# Set permissions
chown ga:ga "$CSV_PATH"

# Record task start time
date +%s > /tmp/task_start_time.txt
stat -c %Y /home/ga/chinook.odb > /tmp/initial_odb_mtime.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "CSV created at: $CSV_PATH"
echo "Expected rows: $(cat /tmp/expected_row_count.txt)"