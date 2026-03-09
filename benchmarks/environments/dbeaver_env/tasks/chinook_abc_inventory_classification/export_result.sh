#!/bin/bash
echo "=== Exporting ABC Classification Results ==="

source /workspace/scripts/task_utils.sh

DB_PATH="/home/ga/Documents/databases/chinook.db"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check DBeaver Connection (parse config)
CONFIG_DIR="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver"
CONNECTION_FOUND="false"
if [ -f "$CONFIG_DIR/data-sources.json" ]; then
    if grep -qi "Chinook" "$CONFIG_DIR/data-sources.json"; then
        CONNECTION_FOUND="true"
    fi
fi

# 3. Check SQL Artifacts (Table Existence & Schema)
TABLE_EXISTS="false"
COLUMNS_VALID="false"
ROW_COUNT=0
AGENT_REVENUE_TOTAL=0
AGENT_A_COUNT=0
AGENT_B_COUNT=0
AGENT_C_COUNT=0

if [ -f "$DB_PATH" ]; then
    # Check table existence
    if sqlite3 "$DB_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name='track_abc_classification';" | grep -q "track_abc_classification"; then
        TABLE_EXISTS="true"
        
        # Check columns
        SCHEMA_INFO=$(sqlite3 "$DB_PATH" "PRAGMA table_info(track_abc_classification);")
        if echo "$SCHEMA_INFO" | grep -q "TrackId" && \
           echo "$SCHEMA_INFO" | grep -q "CumulativePct" && \
           echo "$SCHEMA_INFO" | grep -q "ABCCategory" && \
           echo "$SCHEMA_INFO" | grep -q "RevenueRank"; then
            COLUMNS_VALID="true"
        fi
        
        # Get Stats from Agent's Table
        ROW_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM track_abc_classification;" 2>/dev/null || echo "0")
        AGENT_REVENUE_TOTAL=$(sqlite3 "$DB_PATH" "SELECT SUM(TotalRevenue) FROM track_abc_classification;" 2>/dev/null || echo "0")
        AGENT_A_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM track_abc_classification WHERE ABCCategory='A';" 2>/dev/null || echo "0")
        AGENT_B_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM track_abc_classification WHERE ABCCategory='B';" 2>/dev/null || echo "0")
        AGENT_C_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM track_abc_classification WHERE ABCCategory='C';" 2>/dev/null || echo "0")
    fi
fi

# 4. Calculate Ground Truth (Dynamic)
# We calculate the actual stats directly from the source tables to compare
GT_JSON=$(sqlite3 "$DB_PATH" <<EOF
WITH sales AS (
    SELECT TrackId, SUM(UnitPrice * Quantity) as Rev
    FROM invoice_items
    GROUP BY TrackId
),
ranked AS (
    SELECT 
        Rev,
        SUM(Rev) OVER (ORDER BY Rev DESC) as RunSum,
        (SELECT SUM(UnitPrice * Quantity) FROM invoice_items) as Total
    FROM sales
),
cats AS (
    SELECT 
        CASE 
            WHEN (RunSum - Rev) * 1.0 / Total < 0.70 THEN 'A'
            WHEN (RunSum - Rev) * 1.0 / Total < 0.90 THEN 'B'
            ELSE 'C'
        END as Cat
    FROM ranked
)
SELECT json_object(
    'total_revenue', (SELECT SUM(Rev) FROM sales),
    'count_a', (SELECT COUNT(*) FROM cats WHERE Cat='A'),
    'count_b', (SELECT COUNT(*) FROM cats WHERE Cat='B'),
    'count_c', (SELECT COUNT(*) FROM cats WHERE Cat='C')
);
EOF
)

# 5. Check Files
CSV_DETAILED="$EXPORT_DIR/abc_classification.csv"
CSV_SUMMARY="$EXPORT_DIR/abc_summary.csv"
SQL_SCRIPT="$SCRIPTS_DIR/abc_analysis.sql"

check_file_status() {
    local f="$1"
    if [ -f "$f" ]; then
        local mtime=$(stat -c %Y "$f" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "created"
        else
            echo "exists_old"
        fi
    else
        echo "missing"
    fi
}

STATUS_DETAILED=$(check_file_status "$CSV_DETAILED")
STATUS_SUMMARY=$(check_file_status "$CSV_SUMMARY")
STATUS_SCRIPT=$(check_file_status "$SQL_SCRIPT")

# 6. Generate JSON Result
cat > /tmp/task_result.json <<EOF
{
    "connection_found": $CONNECTION_FOUND,
    "table_exists": $TABLE_EXISTS,
    "columns_valid": $COLUMNS_VALID,
    "agent_stats": {
        "row_count": $ROW_COUNT,
        "total_revenue": ${AGENT_REVENUE_TOTAL:-0},
        "count_a": $AGENT_A_COUNT,
        "count_b": $AGENT_B_COUNT,
        "count_c": $AGENT_C_COUNT
    },
    "ground_truth": ${GT_JSON:-"{}"},
    "files": {
        "detailed_csv": "$STATUS_DETAILED",
        "summary_csv": "$STATUS_SUMMARY",
        "sql_script": "$STATUS_SCRIPT"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json