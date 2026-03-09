#!/bin/bash
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

DB_PATH="/home/ga/Documents/databases/chinook.db"
CSV_PATH="/home/ga/Documents/exports/new_release_manifest.csv"
SQL_PATH="/home/ga/Documents/scripts/remaster_release.sql"
HIDDEN_GT="/root/.ground_truth_top10.json"

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Files
CSV_EXISTS="false"
[ -f "$CSV_PATH" ] && CSV_EXISTS="true"

SQL_EXISTS="false"
[ -f "$SQL_PATH" ] && SQL_EXISTS="true"

# 2. Check Database State
ALBUM_FOUND="false"
ALBUM_ID=""
TRACK_COUNT=0
CORRECT_PRICE_COUNT=0
SUFFIX_MATCH_COUNT=0
CONTENT_MATCH_COUNT=0

if [ -f "$DB_PATH" ]; then
    # Find the album
    ALBUM_INFO=$(sqlite3 "$DB_PATH" "SELECT AlbumId FROM albums WHERE Title='Iron Maiden: Remastered Classics' AND ArtistId=90 LIMIT 1;")
    
    if [ -n "$ALBUM_INFO" ]; then
        ALBUM_FOUND="true"
        ALBUM_ID="$ALBUM_INFO"
        
        # Analyze tracks in this album
        # Get ms and bytes to compare with ground truth
        # Also check price and name suffix
        python3 << PYEOF
import sqlite3
import json
import os

conn = sqlite3.connect('$DB_PATH')
conn.row_factory = sqlite3.Row
c = conn.cursor()

album_id = $ALBUM_ID
ground_truth = []
if os.path.exists('$HIDDEN_GT'):
    with open('$HIDDEN_GT') as f:
        ground_truth = json.load(f)

# Get tracks for new album
rows = c.execute("SELECT Name, UnitPrice, Milliseconds, Bytes FROM tracks WHERE AlbumId=?", (album_id,)).fetchall()

track_count = len(rows)
correct_price = 0
suffix_match = 0
content_match = 0

# Create a set of (ms, bytes) from ground truth for matching
gt_signatures = set((t['ms'], t['bytes']) for t in ground_truth)

for r in rows:
    # Check Price (allow float tolerance)
    if abs(r['UnitPrice'] - 1.29) < 0.01:
        correct_price += 1
        
    # Check Name Suffix
    if str(r['Name']).endswith(" (Remastered)"):
        suffix_match += 1
        
    # Check Content (Signature match)
    sig = (r['Milliseconds'], r['Bytes'])
    if sig in gt_signatures:
        content_match += 1
        # Remove to handle duplicates if any (though unlikely for distinct tracks)
        # gt_signatures.remove(sig) 

result = {
    "track_count": track_count,
    "correct_price_count": correct_price,
    "suffix_match_count": suffix_match,
    "content_match_count": content_match,
    "gt_size": len(ground_truth)
}

with open('/tmp/db_analysis.json', 'w') as f:
    json.dump(result, f)
PYEOF
    fi
fi

# Load DB analysis results
if [ -f "/tmp/db_analysis.json" ]; then
    TRACK_COUNT=$(jq .track_count /tmp/db_analysis.json)
    CORRECT_PRICE_COUNT=$(jq .correct_price_count /tmp/db_analysis.json)
    SUFFIX_MATCH_COUNT=$(jq .suffix_match_count /tmp/db_analysis.json)
    CONTENT_MATCH_COUNT=$(jq .content_match_count /tmp/db_analysis.json)
fi

# Final Screenshot
take_screenshot /tmp/task_final.png

# Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "csv_exists": $CSV_EXISTS,
    "sql_exists": $SQL_EXISTS,
    "album_found": $ALBUM_FOUND,
    "track_count": $TRACK_COUNT,
    "correct_price_count": $CORRECT_PRICE_COUNT,
    "suffix_match_count": $SUFFIX_MATCH_COUNT,
    "content_match_count": $CONTENT_MATCH_COUNT,
    "timestamp": $(date +%s)
}
EOF

# Output for logs
cat /tmp/task_result.json