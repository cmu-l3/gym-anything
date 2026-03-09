#!/bin/bash
# Export script for chinook_audio_audit
# Verifies database state via sqlite3 and checks output files

echo "=== Exporting Chinook Audio Audit Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Paths
DB_PATH="/home/ga/Documents/databases/chinook.db"
CSV_PATH="/home/ga/Documents/exports/hifi_candidates.csv"
SQL_PATH="/home/ga/Documents/scripts/genre_quality.sql"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- 1. Verify DBeaver Connection ---
# Check if "Chinook" connection exists in DBeaver config
CONFIG_DIR="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver"
CONNECTION_EXISTS="false"
if [ -f "$CONFIG_DIR/data-sources.json" ]; then
    # Simple grep check for the name
    if grep -qi "\"name\": \"Chinook\"" "$CONFIG_DIR/data-sources.json"; then
        CONNECTION_EXISTS="true"
    fi
fi

# --- 2. Verify View Existence & Logic ---
VIEW_EXISTS="false"
VIEW_SQL=""
VIDEO_IN_VIEW_COUNT=-1
CALCULATION_CHECK_DIFF=-1

if [ -f "$DB_PATH" ]; then
    # Check if view exists
    VIEW_CHECK=$(sqlite3 "$DB_PATH" "SELECT count(*) FROM sqlite_master WHERE type='view' AND name='v_track_bitrates';")
    
    if [ "$VIEW_CHECK" -eq "1" ]; then
        VIEW_EXISTS="true"
        # Get view definition
        VIEW_SQL=$(sqlite3 "$DB_PATH" "SELECT sql FROM sqlite_master WHERE type='view' AND name='v_track_bitrates';")
        
        # Check if view filters out video
        # We know 'Protected MPEG-4 video file' is MediaType 3. 
        # Let's query the view for any rows where MediaType contains 'video'
        VIDEO_IN_VIEW_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM v_track_bitrates WHERE MediaType LIKE '%video%';")
        
        # Verify calculation on a specific track (TrackId 1)
        # Track 1: Bytes=11170334, Milliseconds=343719
        # Expected: (11170334 * 8) / 343719 = 259.99 -> 260
        AGENT_CALC=$(sqlite3 "$DB_PATH" "SELECT BitrateKbps FROM v_track_bitrates WHERE TrackId=1;" 2>/dev/null || echo "0")
        EXPECTED_CALC=260
        # Calculate difference (abs)
        CALCULATION_CHECK_DIFF=$(echo "$AGENT_CALC - $EXPECTED_CALC" | bc 2>/dev/null | tr -d '-')
        if [ -z "$CALCULATION_CHECK_DIFF" ]; then CALCULATION_CHECK_DIFF=999; fi
    fi
fi

# --- 3. Verify CSV Export ---
CSV_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
CSV_ROW_COUNT=0
CSV_HAS_VIDEO="false"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    
    # Check creation time
    FILE_TIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
    
    # Count rows (minus header)
    CSV_ROW_COUNT=$(($(wc -l < "$CSV_PATH") - 1))
    
    # Check for video content in CSV (grep for "video")
    if grep -qi "video" "$CSV_PATH"; then
        CSV_HAS_VIDEO="true"
    fi
fi

# --- 4. Verify SQL Script ---
SQL_EXISTS="false"
if [ -f "$SQL_PATH" ]; then
    SQL_EXISTS="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/audit_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "connection_exists": $CONNECTION_EXISTS,
    "view_exists": $VIEW_EXISTS,
    "view_sql": "$(echo $VIEW_SQL | sed 's/"/\\"/g')",
    "video_in_view_count": $VIDEO_IN_VIEW_COUNT,
    "calculation_diff": $CALCULATION_CHECK_DIFF,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_has_video": $CSV_HAS_VIDEO,
    "sql_script_exists": $SQL_EXISTS,
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json