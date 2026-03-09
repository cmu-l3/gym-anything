#!/bin/bash
echo "=== Exporting Catalog Integrity Audit results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state
take_screenshot /tmp/task_final.png

# 2. Close LibreOffice to ensure ODB is flushed to disk
# (Base writes to the .odb zip file on save, but mostly on exit)
echo "Closing LibreOffice to flush changes..."
kill_libreoffice

# 3. Check if output file was modified
ODB_PATH="/home/ga/chinook.odb"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ODB_MODIFIED="false"
ODB_SIZE="0"

if [ -f "$ODB_PATH" ]; then
    ODB_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
        ODB_MODIFIED="true"
    fi
    ODB_SIZE=$(stat -c %s "$ODB_PATH" 2>/dev/null || echo "0")
fi

# 4. Generate Ground Truth from the source SQLite file
# We calculate the expected orphans/gaps using Python/SQLite to compare against agent's work
echo "Generating ground truth data..."
python3 -c "
import sqlite3
import json

conn = sqlite3.connect('/opt/libreoffice_base_samples/Chinook_Sqlite.sqlite')
cursor = conn.cursor()

ground_truth = {}

# Orphan Artists (Artist left join Album, Album is null)
cursor.execute('SELECT a.ArtistId, a.Name FROM Artist a LEFT JOIN Album al ON a.ArtistId = al.ArtistId WHERE al.AlbumId IS NULL')
rows = cursor.fetchall()
ground_truth['AuditOrphanArtists'] = [{'ArtistId': r[0], 'Name': r[1]} for r in rows]
ground_truth['Count_OrphanArtists'] = len(rows)

# Empty Albums (Album left join Track, Track is null)
cursor.execute('SELECT al.AlbumId, al.Title, al.ArtistId FROM Album al LEFT JOIN Track t ON al.AlbumId = t.AlbumId WHERE t.TrackId IS NULL')
rows = cursor.fetchall()
ground_truth['AuditEmptyAlbums'] = [{'AlbumId': r[0], 'Title': r[1], 'ArtistId': r[2]} for r in rows]
ground_truth['Count_EmptyAlbums'] = len(rows)

# Unused Genres (Genre left join Track, Track is null)
cursor.execute('SELECT g.GenreId, g.Name FROM Genre g LEFT JOIN Track t ON g.GenreId = t.GenreId WHERE t.TrackId IS NULL')
rows = cursor.fetchall()
ground_truth['AuditUnusedGenres'] = [{'GenreId': r[0], 'Name': r[1]} for r in rows]
ground_truth['Count_UnusedGenres'] = len(rows)

# Inactive Customers (Customer left join Invoice, Invoice is null)
cursor.execute('SELECT c.CustomerId, c.FirstName, c.LastName, c.Email FROM Customer c LEFT JOIN Invoice i ON c.CustomerId = i.CustomerId WHERE i.InvoiceId IS NULL')
rows = cursor.fetchall()
ground_truth['AuditInactiveCustomers'] = [{'CustomerId': r[0], 'FirstName': r[1], 'LastName': r[2], 'Email': r[3]} for r in rows]
ground_truth['Count_InactiveCustomers'] = len(rows)

conn.close()

with open('/tmp/ground_truth.json', 'w') as f:
    json.dump(ground_truth, f, indent=2)
"

# 5. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $(date +%s),
    "odb_modified": $ODB_MODIFIED,
    "odb_size": $ODB_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "odb_path": "$ODB_PATH",
    "ground_truth_path": "/tmp/ground_truth.json"
}
EOF

# Move result to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Copy ODB and Ground Truth for verifier access
cp "$ODB_PATH" /tmp/submitted_chinook.odb
chmod 666 /tmp/submitted_chinook.odb
chmod 666 /tmp/ground_truth.json

echo "=== Export complete ==="