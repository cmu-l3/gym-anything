#!/bin/bash
# export_result.sh - Post-task hook for usgs_earthquake_data_analysis

echo "=== Exporting USGS Earthquake Data Analysis results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Kill Firefox to flush database WAL to disk
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Load Task Context
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")

if [ -z "$PROFILE_DIR" ] || [ ! -f "$PROFILE_DIR/places.sqlite" ]; then
    # Try to find again if setup failed to record it
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null || echo "")
fi
PLACES_DB="$PROFILE_DIR/places.sqlite"

# ==============================================================================
# DATA EXTRACTION
# ==============================================================================

# A. CHECK CSV DOWNLOAD
CSV_PATH="/home/ga/Downloads/earthquake_data.csv"
CSV_EXISTS="false"
CSV_FRESH="false"
CSV_ROWS=0
CSV_HAS_HEADERS="false"
CSV_SIZE_BYTES=0

# If specific file not found, look for default USGS name "query.csv"
if [ ! -f "$CSV_PATH" ]; then
    ALT_CSV=$(find /home/ga/Downloads -name "query*.csv" -newer /tmp/task_start_timestamp 2>/dev/null | head -1)
    if [ -n "$ALT_CSV" ]; then
        echo "Found alternative CSV: $ALT_CSV"
        CSV_PATH="$ALT_CSV"
    fi
fi

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_SIZE_BYTES=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_FRESH="true"
    fi
    
    # Analyze CSV content
    if [ "$CSV_SIZE_BYTES" -gt 100 ]; then
        # Count rows (excluding header)
        CSV_ROWS=$(($(wc -l < "$CSV_PATH") - 1))
        
        # Check headers
        HEADER_LINE=$(head -n 1 "$CSV_PATH" | tr '[:upper:]' '[:lower:]')
        if [[ "$HEADER_LINE" == *"time"* && "$HEADER_LINE" == *"mag"* && "$HEADER_LINE" == *"latitude"* ]]; then
            CSV_HAS_HEADERS="true"
        fi
    fi
fi

# B. CHECK REPORT FILE
REPORT_PATH="/home/ga/Documents/earthquake_analysis.txt"
REPORT_EXISTS="false"
REPORT_FRESH="false"
REPORT_CONTENT=""
REPORT_HAS_COUNT="false"
REPORT_HAS_USGS="false"
REPORT_HAS_MAGNITUDE="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_FRESH="true"
    fi
    
    # Read content for Python verification (limit size)
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 5000)
    
    # Simple grep checks
    if grep -qi "USGS" "$REPORT_PATH"; then REPORT_HAS_USGS="true"; fi
    if grep -qi "Magnitude" "$REPORT_PATH" || grep -qi "Mag" "$REPORT_PATH"; then REPORT_HAS_MAGNITUDE="true"; fi
    # Check for numbers (potential counts)
    if grep -qE "[0-9]+" "$REPORT_PATH"; then REPORT_HAS_COUNT="true"; fi
fi

# C. CHECK BROWSER HISTORY & BOOKMARKS
USGS_VISITS=0
BOOKMARK_FOLDER_EXISTS="false"
BOOKMARK_COUNT=0
BOOKMARK_USGS_COUNT=0

if [ -f "$PLACES_DB" ]; then
    # Copy DB to temp to avoid locks
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    
    # Check History
    USGS_VISITS=$(sqlite3 "$TEMP_DB" \
        "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id
         WHERE p.url LIKE '%earthquake.usgs.gov%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
         
    # Check Bookmarks
    FOLDER_ID=$(sqlite3 "$TEMP_DB" \
        "SELECT id FROM moz_bookmarks WHERE type=2 AND lower(title) = 'usgs earthquake research' LIMIT 1;" 2>/dev/null || echo "")
        
    if [ -n "$FOLDER_ID" ]; then
        BOOKMARK_FOLDER_EXISTS="true"
        
        # Count bookmarks in this folder
        BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1 AND parent=${FOLDER_ID};" 2>/dev/null || echo "0")
            
        # Count bookmarks with USGS URL in this folder
        BOOKMARK_USGS_COUNT=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id
             WHERE b.type=1 AND b.parent=${FOLDER_ID} AND p.url LIKE '%usgs.gov%';" 2>/dev/null || echo "0")
    fi
    
    rm -f "$TEMP_DB"
fi

# ==============================================================================
# GENERATE JSON RESULT
# ==============================================================================
# Use Python to generate safe JSON
python3 << PYEOF
import json
import os

result = {
    "csv_exists": $CSV_EXISTS,
    "csv_fresh": $CSV_FRESH,
    "csv_rows": $CSV_ROWS,
    "csv_has_headers": $CSV_HAS_HEADERS,
    "csv_size_bytes": $CSV_SIZE_BYTES,
    "csv_path": "$CSV_PATH",
    
    "report_exists": $REPORT_EXISTS,
    "report_fresh": $REPORT_FRESH,
    "report_has_usgs": $REPORT_HAS_USGS,
    "report_has_magnitude": $REPORT_HAS_MAGNITUDE,
    "report_content_preview": """$REPORT_CONTENT""",
    
    "usgs_visits": $USGS_VISITS,
    "bookmark_folder_exists": $BOOKMARK_FOLDER_EXISTS,
    "bookmark_count": $BOOKMARK_COUNT,
    "bookmark_usgs_count": $BOOKMARK_USGS_COUNT,
    
    "task_start_ts": $TASK_START
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Ensure readable
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json