#!/bin/bash
echo "=== Exporting Web Log Forensics Result ==="

source /workspace/scripts/task_utils.sh

# Paths
DB_PATH="/home/ga/Documents/databases/investigation.db"
OUTPUT_CSV="/home/ga/Documents/exports/breach_evidence.csv"
GT_FILE="/tmp/forensic_ground_truth.json"

# Capture final state
take_screenshot /tmp/task_final.png

# Initialize result variables
DB_EXISTS="false"
TABLE_EXISTS="false"
ROW_COUNT=0
STATUS_IS_NUMERIC="false"
OUTPUT_EXISTS="false"
OUTPUT_CREATED_DURING_TASK="false"
OUTPUT_HAS_ATTACKER="false"
OUTPUT_HAS_BREACH="false"
OUTPUT_ROW_COUNT=0

# 1. Verify Database
if [ -f "$DB_PATH" ]; then
    DB_EXISTS="true"
    
    # Verify table creation and data import
    ROW_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM web_logs;" 2>/dev/null || echo 0)
    if [ "$ROW_COUNT" -gt 0 ]; then
        TABLE_EXISTS="true"
        
        # Verify schema data type (heuristic: check if status_code sum is valid number)
        # In SQLite, types are dynamic, but we want to see if they imported it properly
        # A simple check is trying a numeric operation
        SUM_STATUS=$(sqlite3 "$DB_PATH" "SELECT SUM(status_code) FROM web_logs;" 2>/dev/null || echo "error")
        if [[ "$SUM_STATUS" =~ ^[0-9]+$ ]]; then
            STATUS_IS_NUMERIC="true"
        fi
    fi
fi

# 2. Verify Output File
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo 0)

if [ -f "$OUTPUT_CSV" ]; then
    OUTPUT_EXISTS="true"
    
    # Check timestamp
    FILE_TIME=$(stat -c %Y "$OUTPUT_CSV" 2>/dev/null || echo 0)
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        OUTPUT_CREATED_DURING_TASK="true"
    fi
    
    # Load Ground Truth
    ATTACKER_IP=$(python3 -c "import json; print(json.load(open('$GT_FILE'))['attacker_ip'])" 2>/dev/null)
    BREACHED_FILE=$(python3 -c "import json; print(json.load(open('$GT_FILE'))['breached_file'])" 2>/dev/null)
    
    # Check content of the CSV
    CSV_CONTENT=$(cat "$OUTPUT_CSV")
    OUTPUT_ROW_COUNT=$(wc -l < "$OUTPUT_CSV")
    OUTPUT_ROW_COUNT=$((OUTPUT_ROW_COUNT - 1)) # subtract header
    
    # Check for Attacker IP (should constitute ALL rows in a perfect export, but we check presence)
    if echo "$CSV_CONTENT" | grep -q "$ATTACKER_IP"; then
        OUTPUT_HAS_ATTACKER="true"
    fi
    
    # Check for Breach File
    if echo "$CSV_CONTENT" | grep -q "$BREACHED_FILE"; then
        OUTPUT_HAS_BREACH="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "db_exists": $DB_EXISTS,
    "table_exists": $TABLE_EXISTS,
    "row_count": $ROW_COUNT,
    "status_is_numeric": $STATUS_IS_NUMERIC,
    "output_exists": $OUTPUT_EXISTS,
    "output_created_during_task": $OUTPUT_CREATED_DURING_TASK,
    "output_has_attacker": $OUTPUT_HAS_ATTACKER,
    "output_has_breach": $OUTPUT_HAS_BREACH,
    "output_row_count": $OUTPUT_ROW_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="