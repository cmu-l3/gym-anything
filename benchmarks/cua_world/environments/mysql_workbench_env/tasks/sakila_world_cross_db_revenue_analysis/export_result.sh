#!/bin/bash
# Export script for sakila_world_cross_db_revenue_analysis task

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Start Time
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 3. Verify Database Objects via MySQL Query
# We query the Information Schema to verify the agent created the requested objects.

# 3.1 Check country_xref table
TABLE_INFO=$(mysql -u root -p'GymAnything#2024' -N -e "
    SELECT COUNT(*) FROM information_schema.TABLES
    WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='country_xref';
" 2>/dev/null)
TABLE_EXISTS=$([ "$TABLE_INFO" = "1" ] && echo "true" || echo "false")

TABLE_ROWS=0
if [ "$TABLE_EXISTS" = "true" ]; then
    TABLE_ROWS=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM country_xref;" 2>/dev/null)
fi

# 3.2 Check v_revenue_demographics view & columns
VIEW_INFO=$(mysql -u root -p'GymAnything#2024' -N -e "
    SELECT COUNT(*) FROM information_schema.VIEWS
    WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='v_revenue_demographics';
" 2>/dev/null)
VIEW_EXISTS=$([ "$VIEW_INFO" = "1" ] && echo "true" || echo "false")

VIEW_COLS=""
if [ "$VIEW_EXISTS" = "true" ]; then
    # Get comma-separated list of columns
    VIEW_COLS=$(mysql -u root -p'GymAnything#2024' -N -e "
        SELECT GROUP_CONCAT(COLUMN_NAME) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='v_revenue_demographics';
    " 2>/dev/null)
fi

# 3.3 Check sp_continent_report procedure
PROC_INFO=$(mysql -u root -p'GymAnything#2024' -N -e "
    SELECT COUNT(*) FROM information_schema.ROUTINES
    WHERE ROUTINE_SCHEMA='sakila' AND ROUTINE_NAME='sp_continent_report' AND ROUTINE_TYPE='PROCEDURE';
" 2>/dev/null)
PROC_EXISTS=$([ "$PROC_INFO" = "1" ] && echo "true" || echo "false")

# 4. Verify Exported CSV Files

# 4.1 Asia Report
ASIA_CSV="/home/ga/Documents/exports/asia_revenue_report.csv"
ASIA_EXISTS="false"
ASIA_ROWS=0
ASIA_CREATED_DURING_TASK="false"
ASIA_HAS_DATA="false"

if [ -f "$ASIA_CSV" ]; then
    ASIA_EXISTS="true"
    ASIA_MTIME=$(stat -c %Y "$ASIA_CSV" 2>/dev/null || echo "0")
    if [ "$ASIA_MTIME" -gt "$TASK_START" ]; then
        ASIA_CREATED_DURING_TASK="true"
    fi
    # Count rows (minus header)
    TOTAL_LINES=$(wc -l < "$ASIA_CSV")
    ASIA_ROWS=$((TOTAL_LINES - 1))
    
    # Simple content check: does it look like it contains Asian countries?
    if grep -qE "India|China|Japan|Thailand" "$ASIA_CSV"; then
        ASIA_HAS_DATA="true"
    fi
fi

# 4.2 Ranking Report
RANK_CSV="/home/ga/Documents/exports/revenue_per_capita_ranking.csv"
RANK_EXISTS="false"
RANK_ROWS=0
RANK_CREATED_DURING_TASK="false"
RANK_HAS_METRIC="false"

if [ -f "$RANK_CSV" ]; then
    RANK_EXISTS="true"
    RANK_MTIME=$(stat -c %Y "$RANK_CSV" 2>/dev/null || echo "0")
    if [ "$RANK_MTIME" -gt "$TASK_START" ]; then
        RANK_CREATED_DURING_TASK="true"
    fi
    TOTAL_LINES=$(wc -l < "$RANK_CSV")
    RANK_ROWS=$((TOTAL_LINES - 1))

    # Check for evidence of the calculated metric (decimal numbers)
    if head -5 "$RANK_CSV" | grep -qE "[0-9]+\.[0-9]+"; then
        RANK_HAS_METRIC="true"
    fi
fi

# 5. Compile Result JSON
# Use a temp file to avoid permission issues, then move to /tmp/task_result.json
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "timestamp": "$CURRENT_TIME",
    "db_objects": {
        "table_exists": $TABLE_EXISTS,
        "table_rows": ${TABLE_ROWS:-0},
        "view_exists": $VIEW_EXISTS,
        "view_columns": "$VIEW_COLS",
        "proc_exists": $PROC_EXISTS
    },
    "files": {
        "asia_report": {
            "exists": $ASIA_EXISTS,
            "created_during_task": $ASIA_CREATED_DURING_TASK,
            "rows": $ASIA_ROWS,
            "has_expected_content": $ASIA_HAS_DATA
        },
        "ranking_report": {
            "exists": $RANK_EXISTS,
            "created_during_task": $RANK_CREATED_DURING_TASK,
            "rows": $RANK_ROWS,
            "has_metric_data": $RANK_HAS_METRIC
        }
    }
}
EOF

# Safe move
chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json