#!/bin/bash
# Export script for Fly Ash Concrete Scenario task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback functions if utils missing
if ! type derby_count &>/dev/null; then
    derby_count() { echo "0"; }
fi
if ! type derby_query &>/dev/null; then
    derby_query() { echo ""; }
fi
if ! type close_openlca &>/dev/null; then
    close_openlca() { pkill -f "openLCA" || true; sleep 2; }
fi

echo "=== Exporting Results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gather File Evidence
OUTPUT_FILE="/home/ga/LCA_Results/fly_ash_concrete_lcia.csv"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
CONTENT_KEYWORDS_FOUND=0
CONTENT_SAMPLE=""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START_TIME" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Read first few lines for keywords check
    CONTENT_SAMPLE=$(head -n 5 "$OUTPUT_FILE" | base64 -w 0)
    
    # Check for critical keywords in the file content
    if grep -iqE "global warming|gwp|climate|co2" "$OUTPUT_FILE"; then
        ((CONTENT_KEYWORDS_FOUND++))
    fi
    if grep -iqE "concrete|cement" "$OUTPUT_FILE"; then
        ((CONTENT_KEYWORDS_FOUND++))
    fi
fi

# 3. Gather Database Evidence
# We must close OpenLCA to query Derby reliably
echo "Closing OpenLCA for verification..."
close_openlca
sleep 5

DB_DIR="/home/ga/openLCA-data-1.4/databases"
PROCESS_COUNT=0
PRODUCT_SYSTEM_COUNT=0
NEW_PROCESS_NAMES=""
DB_NAME=""
DB_SIZE_MB=0

# Find active database (most recently modified or largest)
ACTIVE_DB=$(ls -td "$DB_DIR"/*/ 2>/dev/null | head -1)

if [ -n "$ACTIVE_DB" ] && [ -d "$ACTIVE_DB" ]; then
    DB_NAME=$(basename "$ACTIVE_DB")
    DB_SIZE_MB=$(du -sm "$ACTIVE_DB" | cut -f1)
    
    # Query counts
    PROCESS_COUNT=$(derby_count "$ACTIVE_DB" "PROCESSES")
    PRODUCT_SYSTEM_COUNT=$(derby_count "$ACTIVE_DB" "PRODUCT_SYSTEMS")
    
    # Query for names of recently created/modified processes or just verify "fly ash" exists in names
    # Note: TBL_PROCESSES has a NAME column
    NEW_PROCESS_QUERY="SELECT NAME FROM TBL_PROCESSES WHERE LOWER(NAME) LIKE '%fly%ash%' OR LOWER(NAME) LIKE '%modified%' OR LOWER(NAME) LIKE '%30%';"
    NEW_PROCESS_NAMES=$(derby_query "$ACTIVE_DB" "$NEW_PROCESS_QUERY")
fi

# 4. Compile JSON Result
cat > /tmp/task_result.json << EOF
{
    "task_start_time": $TASK_START_TIME,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "content_keywords_score": $CONTENT_KEYWORDS_FOUND,
    "content_sample_base64": "$CONTENT_SAMPLE",
    "db_found": "$DB_NAME",
    "db_size_mb": $DB_SIZE_MB,
    "process_count": ${PROCESS_COUNT:-0},
    "product_system_count": ${PRODUCT_SYSTEM_COUNT:-0},
    "fly_ash_process_found": "$(echo "$NEW_PROCESS_NAMES" | tr -d '\n' | sed 's/"/\\"/g')",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions so python verifier can read it
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json