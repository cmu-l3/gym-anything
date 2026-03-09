#!/bin/bash
# Export script for chinook_viral_track_analysis
# Collects artifacts and prepares result JSON

echo "=== Exporting Viral Track Analysis Result ==="

source /workspace/scripts/task_utils.sh

# Configuration
RESULT_CSV="/home/ga/Documents/exports/viral_tracks.csv"
RESULT_SQL="/home/ga/Documents/scripts/viral_analysis.sql"
CONFIG_DIR="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver"
GROUND_TRUTH="/tmp/ground_truth.csv"

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check Connection
CONNECTION_EXISTS="false"
if [ -f "$CONFIG_DIR/data-sources.json" ]; then
    if grep -q "ChinookViral" "$CONFIG_DIR/data-sources.json"; then
        CONNECTION_EXISTS="true"
    fi
fi

# 3. Check CSV Output
CSV_EXISTS="false"
CSV_COLUMNS_VALID="false"
ROW_COUNT=0
CSV_CONTENT=""

if [ -f "$RESULT_CSV" ]; then
    CSV_EXISTS="true"
    ROW_COUNT=$(($(wc -l < "$RESULT_CSV") - 1)) # Minus header
    
    # Read first few lines for verification
    CSV_CONTENT=$(head -n 5 "$RESULT_CSV" | base64 -w 0)
    
    # Check headers
    HEADERS=$(head -n 1 "$RESULT_CSV")
    REQUIRED_HEADERS=("AlbumTitle" "TrackName" "TrackRevenue" "AlbumAvgRevenue" "RevenueMultiplier")
    MISSING_HEADER="false"
    for h in "${REQUIRED_HEADERS[@]}"; do
        if [[ ! "$HEADERS" =~ "$h" ]]; then
            MISSING_HEADER="true"
        fi
    done
    if [ "$MISSING_HEADER" == "false" ]; then
        CSV_COLUMNS_VALID="true"
    fi
fi

# 4. Check SQL Script
SQL_EXISTS="false"
SQL_CONTENT=""
if [ -f "$RESULT_SQL" ]; then
    SQL_EXISTS="true"
    # Capture script content for keyword analysis
    SQL_CONTENT=$(cat "$RESULT_SQL" | base64 -w 0)
fi

# 5. Get Ground Truth for comparison
GT_CONTENT=""
if [ -f "$GROUND_TRUTH" ]; then
    GT_CONTENT=$(cat "$GROUND_TRUTH" | base64 -w 0)
fi

# 6. Timing Checks (Anti-gaming)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_CREATED_DURING_TASK="false"
if [ "$CSV_EXISTS" == "true" ]; then
    FILE_TIME=$(stat -c %Y "$RESULT_CSV")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 7. Generate Result JSON
cat > /tmp/task_result.json <<EOF
{
    "connection_exists": $CONNECTION_EXISTS,
    "csv_exists": $CSV_EXISTS,
    "csv_columns_valid": $CSV_COLUMNS_VALID,
    "row_count": $ROW_COUNT,
    "csv_content_b64": "$CSV_CONTENT",
    "sql_exists": $SQL_EXISTS,
    "sql_content_b64": "$SQL_CONTENT",
    "ground_truth_b64": "$GT_CONTENT",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "timestamp": $(date +%s)
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"