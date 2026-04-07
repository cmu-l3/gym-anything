#!/bin/bash
# Export script for Electricity Grid Mix Data Audit
# Captures the CSV file, screenshots, and verification data from Derby

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type derby_query &>/dev/null; then
    derby_query() { echo ""; }
fi
if ! type close_openlca &>/dev/null; then
    close_openlca() { pkill -f "openLCA\|openlca" 2>/dev/null || true; sleep 3; }
fi

echo "=== Exporting Electricity Grid Audit Result ==="

# 1. Capture final screenshot
take_screenshot /tmp/task_end_screenshot.png
echo "Final screenshot saved."

# 2. Check for Output File
RESULTS_DIR="/home/ga/LCA_Results"
OUTPUT_FILE="$RESULTS_DIR/electricity_audit.csv"
FILE_EXISTS="false"
FILE_SIZE_BYTES=0
FILE_CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE_BYTES=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Copy file to temp for safe reading
    cp "$OUTPUT_FILE" /tmp/agent_audit.csv
else
    # Check if they saved it with a slightly different name
    ALT_FILE=$(find "$RESULTS_DIR" -maxdepth 1 -name "*electricity*.csv" -newermt "@$TASK_START" | head -n 1)
    if [ -n "$ALT_FILE" ]; then
        OUTPUT_FILE="$ALT_FILE"
        FILE_EXISTS="true"
        FILE_SIZE_BYTES=$(stat -c %s "$ALT_FILE" 2>/dev/null || echo "0")
        FILE_CREATED_DURING_TASK="true"
        cp "$ALT_FILE" /tmp/agent_audit.csv
        echo "Found alternative file: $ALT_FILE"
    fi
fi

# 3. Ground Truth Generation (Query Derby)
# We need to know what processes are actually in the DB to compare against agent's CSV
echo "Generating ground truth from Derby..."

# Find active database
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_SIZE=0

# Close OpenLCA to unlock Derby
close_openlca
sleep 3

for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    CURRENT_SIZE=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${CURRENT_SIZE:-0}" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="${CURRENT_SIZE:-0}"
        ACTIVE_DB="$db_path"
    fi
done

DB_IMPORTED="false"
GROUND_TRUTH_COUNT=0
GROUND_TRUTH_NAMES=""

if [ -n "$ACTIVE_DB" ] && [ "${MAX_SIZE:-0}" -gt 10 ]; then
    DB_IMPORTED="true"
    echo "Examining database: $(basename "$ACTIVE_DB")"
    
    # Query for electricity processes
    # We want names of processes that look like electricity generation
    QUERY="SELECT NAME FROM TBL_PROCESSES WHERE LOWER(NAME) LIKE '%electricity%' OR LOWER(NAME) LIKE '%grid%' OR LOWER(NAME) LIKE '%power%';"
    
    # Execute query
    QUERY_RESULT=$(derby_query "$ACTIVE_DB" "$QUERY")
    
    # Clean up result (remove ij headers)
    CLEAN_NAMES=$(echo "$QUERY_RESULT" | grep -v "rows selected" | grep -v "^ij>" | grep -v "^-" | grep -v "^NAME" | sed '/^$/d' | xargs -d '\n')
    
    # Save to file for verifier
    echo "$CLEAN_NAMES" > /tmp/ground_truth_names.txt
    
    # Count them
    GROUND_TRUTH_COUNT=$(echo "$CLEAN_NAMES" | wc -l)
    
    # Store top 20 names for direct JSON inclusion
    GROUND_TRUTH_SAMPLE=$(echo "$CLEAN_NAMES" | head -n 20 | tr '\n' '|' | sed 's/|$//')
else
    echo "No populated database found."
fi

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task": "electricity_grid_audit",
    "file_exists": $FILE_EXISTS,
    "file_path": "$OUTPUT_FILE",
    "file_size": $FILE_SIZE_BYTES,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "db_imported": $DB_IMPORTED,
    "ground_truth_count": $GROUND_TRUTH_COUNT,
    "ground_truth_sample": "$GROUND_TRUTH_SAMPLE",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Also make the CSV and ground truth list available for copy_from_env
if [ -f "/tmp/agent_audit.csv" ]; then
    chmod 666 /tmp/agent_audit.csv 2>/dev/null || true
fi
if [ -f "/tmp/ground_truth_names.txt" ]; then
    chmod 666 /tmp/ground_truth_names.txt 2>/dev/null || true
fi

echo "Result export complete."
cat /tmp/task_result.json