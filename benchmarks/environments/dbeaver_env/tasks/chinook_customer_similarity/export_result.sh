#!/bin/bash
# Export script for chinook_customer_similarity task

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Files
CSV_PATH="/home/ga/Documents/exports/customer_similarity.csv"
SQL_PATH="/home/ga/Documents/scripts/similarity_query.sql"
GT_PATH="/tmp/chinook_ground_truth.json"
RESULT_JSON="/tmp/task_result.json"
CONFIG_DIR="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver"

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final_state.png

# 2. Check DBeaver Connection
CONNECTION_EXISTS="false"
CONNECTION_CORRECT="false"
if [ -f "$CONFIG_DIR/data-sources.json" ]; then
    # Look for name "Chinook" and path "chinook.db"
    if grep -q '"name": "Chinook"' "$CONFIG_DIR/data-sources.json"; then
        CONNECTION_EXISTS="true"
        if grep -q "chinook.db" "$CONFIG_DIR/data-sources.json"; then
            CONNECTION_CORRECT="true"
        fi
    fi
fi

# 3. Check CSV Output
CSV_EXISTS="false"
CSV_ROW_COUNT=0
CSV_COLUMNS_VALID="false"
CSV_FRESH="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo 0)

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    
    # Check timestamp
    FILE_TIME=$(stat -c %Y "$CSV_PATH")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        CSV_FRESH="true"
    fi

    # Check row count (subtract header)
    LINE_COUNT=$(wc -l < "$CSV_PATH")
    CSV_ROW_COUNT=$((LINE_COUNT - 1))

    # Check Columns (simple grep for key columns)
    HEADER=$(head -n 1 "$CSV_PATH")
    if echo "$HEADER" | grep -q "CustomerIdA" && \
       echo "$HEADER" | grep -q "CustomerIdB" && \
       echo "$HEADER" | grep -q "JaccardSimilarity"; then
        CSV_COLUMNS_VALID="true"
    fi
fi

# 4. Check SQL Script
SQL_EXISTS="false"
if [ -f "$SQL_PATH" ]; then
    SQL_EXISTS="true"
fi

# 5. Prepare data for python verifier
# We need to expose the actual CSV content to the verifier safely.
# Since we use copy_from_env in the verifier, we can just point to the files.
# But let's create a summary JSON here.

cat > "$RESULT_JSON" << EOF
{
    "connection_exists": $CONNECTION_EXISTS,
    "connection_correct": $CONNECTION_CORRECT,
    "csv_exists": $CSV_EXISTS,
    "csv_fresh": $CSV_FRESH,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_columns_valid": $CSV_COLUMNS_VALID,
    "sql_exists": $SQL_EXISTS,
    "csv_path": "$CSV_PATH",
    "gt_path": "$GT_PATH",
    "timestamp": "$(date)"
}
EOF

echo "Results exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="