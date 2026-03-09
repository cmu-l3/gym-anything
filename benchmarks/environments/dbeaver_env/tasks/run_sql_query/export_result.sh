#!/bin/bash
# Export script for run_sql_query task
# Verifies actual query execution by checking output file with results

echo "=== Exporting Run SQL Query Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Expected values
EXPECTED_TRACKS=18
EXPECTED_OUTPUT="/home/ga/Documents/exports/acdc_tracks.csv"

# Initialize variables
DBEAVER_RUNNING=$(is_dbeaver_running)
QUERY_EXECUTED="false"
OUTPUT_FILE_EXISTS="false"
OUTPUT_ROW_COUNT=0
CORRECT_TRACK_COUNT="false"
TRACKS_FOUND=""
KNOWN_TRACKS_MATCHED=0

# Known AC/DC track names (partial list for validation)
KNOWN_TRACKS=("For Those About To Rock" "Put The Finger On You" "Let There Be Rock" "Hell Aint A Bad Place To Be" "Whole Lotta Rosie" "Dog Eat Dog" "Problem Child")

echo "Checking for query output file at: $EXPECTED_OUTPUT"

# PRIMARY CHECK: Verify the output file exists with correct content
if [ -f "$EXPECTED_OUTPUT" ]; then
    OUTPUT_FILE_EXISTS="true"
    echo "Output file found!"

    # Count rows (excluding header)
    TOTAL_LINES=$(wc -l < "$EXPECTED_OUTPUT")
    OUTPUT_ROW_COUNT=$((TOTAL_LINES - 1))
    echo "Output has $OUTPUT_ROW_COUNT data rows"

    # Check if row count matches expected
    if [ "$OUTPUT_ROW_COUNT" -ge 17 ] && [ "$OUTPUT_ROW_COUNT" -le 19 ]; then
        CORRECT_TRACK_COUNT="true"
        echo "Track count is correct (expected ~18, got $OUTPUT_ROW_COUNT)"
    fi

    # Read file content
    FILE_CONTENT=$(cat "$EXPECTED_OUTPUT")

    # Verify known AC/DC tracks are present
    for track in "${KNOWN_TRACKS[@]}"; do
        if echo "$FILE_CONTENT" | grep -qi "$track"; then
            KNOWN_TRACKS_MATCHED=$((KNOWN_TRACKS_MATCHED + 1))
            TRACKS_FOUND="${TRACKS_FOUND}${track}, "
        fi
    done

    echo "Matched $KNOWN_TRACKS_MATCHED of ${#KNOWN_TRACKS[@]} known AC/DC tracks"
    echo "Found tracks: $TRACKS_FOUND"

    # Query is considered executed if we have the output file with correct data
    if [ "$CORRECT_TRACK_COUNT" = "true" ] && [ "$KNOWN_TRACKS_MATCHED" -ge 3 ]; then
        QUERY_EXECUTED="true"
        echo "Query execution VERIFIED via output file"
    fi

    # Show file content
    echo ""
    echo "Output file contents (first 10 lines):"
    head -10 "$EXPECTED_OUTPUT"
else
    echo "Output file NOT found at expected path"
    echo ""
    echo "Contents of exports directory:"
    ls -la /home/ga/Documents/exports/ 2>/dev/null || echo "Directory does not exist"
fi

# SECONDARY CHECK: Look for SQL query in DBeaver files (for partial credit)
SQL_QUERY=""
SQL_FILE_FOUND="false"

# Check DBeaver Scripts folder
SCRIPTS_DIR="/home/ga/.local/share/DBeaverData/workspace6/General/Scripts"
if [ -d "$SCRIPTS_DIR" ]; then
    for script in "$SCRIPTS_DIR"/*.sql; do
        if [ -f "$script" ]; then
            SCRIPT_CONTENT=$(cat "$script" 2>/dev/null)
            if echo "$SCRIPT_CONTENT" | grep -qi "ac/dc\|acdc"; then
                SQL_QUERY="$SCRIPT_CONTENT"
                SQL_FILE_FOUND="true"
                echo "Found SQL file with AC/DC reference: $script"
                break
            fi
        fi
    done
fi

# Check SQL history
HISTORY_FILE="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/sql-manager-query-log.json"
if [ -f "$HISTORY_FILE" ] && [ "$SQL_FILE_FOUND" = "false" ]; then
    RECENT_QUERY=$(python3 -c "
import json
try:
    with open('$HISTORY_FILE', 'r') as f:
        data = json.load(f)
    for q in reversed(data.get('queries', [])):
        text = q.get('text', '')
        if 'ac/dc' in text.lower() or 'acdc' in text.lower():
            print(text[:500])
            break
except:
    pass
" 2>/dev/null)
    if [ -n "$RECENT_QUERY" ]; then
        SQL_QUERY="$RECENT_QUERY"
        SQL_FILE_FOUND="true"
        echo "Found AC/DC query in history"
    fi
fi

# Escape SQL query for JSON
SQL_QUERY_ESCAPED=$(echo "$SQL_QUERY" | tr '\n' ' ' | sed 's/"/\\"/g' | head -c 500)
TRACKS_FOUND_ESCAPED=$(echo "$TRACKS_FOUND" | sed 's/"/\\"/g')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/query_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "dbeaver_running": $DBEAVER_RUNNING,
    "query_executed": $QUERY_EXECUTED,
    "output_file_exists": $OUTPUT_FILE_EXISTS,
    "output_file_path": "$EXPECTED_OUTPUT",
    "output_row_count": $OUTPUT_ROW_COUNT,
    "correct_track_count": $CORRECT_TRACK_COUNT,
    "known_tracks_matched": $KNOWN_TRACKS_MATCHED,
    "tracks_found": "$TRACKS_FOUND_ESCAPED",
    "sql_file_found": $SQL_FILE_FOUND,
    "sql_query": "$SQL_QUERY_ESCAPED",
    "expected_track_count": $EXPECTED_TRACKS,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/query_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/query_result.json
chmod 666 /tmp/query_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/query_result.json"
cat /tmp/query_result.json

echo ""
echo "=== Export Complete ==="
