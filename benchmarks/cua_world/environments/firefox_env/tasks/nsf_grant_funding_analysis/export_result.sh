#!/bin/bash
# export_result.sh - Post-task hook for nsf_grant_funding_analysis
# Exports verification data: history, bookmarks, and output file content

echo "=== Exporting nsf_grant_funding_analysis results ==="

# 1. Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Flush Firefox Database (Kill process)
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Load Context
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
PLACES_DB="$PROFILE_DIR/places.sqlite"

# 4. Analyze Browser State (Bookmarks & History)
NSF_VISITS=0
BOOKMARK_FOLDER_EXISTS=0
BOOKMARK_COUNT_IN_FOLDER=0
NSF_BOOKMARKS_IN_FOLDER=0

if [ -f "$PLACES_DB" ]; then
    # Checkpoint WAL
    sqlite3 "$PLACES_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    
    if [ -f "$TEMP_DB" ]; then
        # Check History for nsf.gov visits
        NSF_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
             WHERE p.url LIKE '%nsf.gov%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
             
        # Check Bookmark Folder "NSF Quantum Grants"
        FOLDER_ID=$(sqlite3 "$TEMP_DB" \
            "SELECT id FROM moz_bookmarks WHERE type=2 AND title='NSF Quantum Grants' LIMIT 1;" 2>/dev/null || echo "")
            
        if [ -n "$FOLDER_ID" ]; then
            BOOKMARK_FOLDER_EXISTS=1
            
            # Count bookmarks inside this folder
            BOOKMARK_COUNT_IN_FOLDER=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=${FOLDER_ID} AND type=1;" 2>/dev/null || echo "0")
                
            # Count how many of those are specifically nsf.gov URLs
            NSF_BOOKMARKS_IN_FOLDER=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id 
                 WHERE b.parent=${FOLDER_ID} AND b.type=1 AND p.url LIKE '%nsf.gov%';" 2>/dev/null || echo "0")
        fi
        
        rm -f "$TEMP_DB"
    fi
fi

# 5. Analyze Output File
OUTPUT_FILE="/home/ga/Documents/nsf_grant_analysis.json"
FILE_EXISTS=0
FILE_FRESH=0
FILE_CONTENT="[]"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS=1
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_FRESH=1
    fi
    # Read content safely (if valid JSON)
    if jq . "$OUTPUT_FILE" >/dev/null 2>&1; then
        FILE_CONTENT=$(cat "$OUTPUT_FILE")
    fi
fi

# 6. Generate Result JSON
# Embedding the user's JSON file content directly allows the verifier to parse it easily
# without needing complex double-copy logic.
PYTHON_SCRIPT=$(cat <<EOF
import json
import sys

try:
    output_content = json.loads('''$FILE_CONTENT''')
except:
    output_content = []

result = {
    "nsf_visits": $NSF_VISITS,
    "bookmark_folder_exists": bool($BOOKMARK_FOLDER_EXISTS),
    "bookmark_count": $BOOKMARK_COUNT_IN_FOLDER,
    "nsf_bookmarks_count": $NSF_BOOKMARKS_IN_FOLDER,
    "file_exists": bool($FILE_EXISTS),
    "file_fresh": bool($FILE_FRESH),
    "output_data": output_content
}

print(json.dumps(result))
EOF
)

python3 -c "$PYTHON_SCRIPT" > /tmp/task_result.json

# 7. Finalize Export
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Export complete. Result:"
cat /tmp/task_result.json