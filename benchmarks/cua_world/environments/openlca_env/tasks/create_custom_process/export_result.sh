#!/bin/bash
# Export script for Custom Process Creation task

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type close_openlca &>/dev/null; then
    close_openlca() { pkill -f "openLCA\|openlca" 2>/dev/null || true; sleep 3; }
fi
if ! type derby_query &>/dev/null; then
    derby_query() { echo ""; }
fi

echo "=== Exporting Custom Process Result ==="

# 1. Capture Final Screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Get Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 3. Verify Result File (CSV Export)
OUTPUT_FILE="/home/ga/LCA_Results/brewery_lca_results.csv"
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
HAS_GWP="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Content check for "Global Warming" or similar
    if grep -qi "global.warm\|GWP\|climate\|CO2" "$OUTPUT_FILE"; then
        HAS_GWP="true"
    fi
else
    # Check if they saved it as Excel (.xlsx) by mistake, but mapped to logic
    ALT_FILE=$(find /home/ga/LCA_Results -name "*brewery*.xlsx" -newer /tmp/task_start_screenshot.png 2>/dev/null | head -1)
    if [ -n "$ALT_FILE" ]; then
        FILE_EXISTS="true_xlsx"
        FILE_SIZE=$(stat -c %s "$ALT_FILE")
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Analyze Database State (The Core Verification)
# We need to close OpenLCA to query the Derby database reliably
close_openlca
sleep 5

DB_DIR="/home/ga/openLCA-data-1.4/databases"
PROCESS_CREATED="false"
EXCHANGES_DEFINED="false"
PRODUCT_SYSTEM_CREATED="false"
LCIA_METHODS_PRESENT="false"
NEW_PROCESS_NAME=""
INPUT_COUNT=0

# Find the active database (largest/most recent)
ACTIVE_DB=""
MAX_SIZE=0
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    DB_SIZE=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${DB_SIZE:-0}" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="${DB_SIZE:-0}"
        ACTIVE_DB="$db_path"
    fi
done

if [ -n "$ACTIVE_DB" ] && [ "${MAX_SIZE:-0}" -gt 5 ]; then
    echo "Analyzing database: $ACTIVE_DB"

    # A. Check for new process with "beer" or "brew" in name
    # TBL_PROCESSES: ID, NAME, ...
    echo "  Querying TBL_PROCESSES..."
    PROCESS_QUERY="SELECT ID, NAME FROM TBL_PROCESSES WHERE LOWER(NAME) LIKE '%beer%' OR LOWER(NAME) LIKE '%brew%';"
    PROCESS_RESULT=$(derby_query "$ACTIVE_DB" "$PROCESS_QUERY")
    
    # Check if we got a result
    if echo "$PROCESS_RESULT" | grep -qi "beer\|brew"; then
        PROCESS_CREATED="true"
        # Extract name roughly
        NEW_PROCESS_NAME=$(echo "$PROCESS_RESULT" | grep -i "beer\|brew" | head -1 | sed 's/^[0-9]*[ \t]*//')
        
        # Get the ID of the new process to check exchanges
        PROCESS_ID=$(echo "$PROCESS_RESULT" | grep -i "beer\|brew" | head -1 | awk '{print $1}')
        
        if [ -n "$PROCESS_ID" ]; then
            # B. Check exchanges for this process
            # TBL_EXCHANGES: F_OWNER (Process ID), IS_INPUT (1/0)
            echo "  Querying TBL_EXCHANGES for Process ID $PROCESS_ID..."
            EXCHANGE_QUERY="SELECT COUNT(*) FROM TBL_EXCHANGES WHERE F_OWNER = $PROCESS_ID AND IS_INPUT = 1;"
            EXCHANGE_COUNT_RAW=$(derby_query "$ACTIVE_DB" "$EXCHANGE_QUERY")
            # Parse count from IJ output (usually the last number)
            INPUT_COUNT=$(echo "$EXCHANGE_COUNT_RAW" | grep -o "[0-9]*" | tail -1)
            
            if [ "${INPUT_COUNT:-0}" -ge 3 ]; then
                EXCHANGES_DEFINED="true"
            fi
        fi
    fi

    # C. Check for Product System
    # TBL_PRODUCT_SYSTEMS: NAME, ...
    echo "  Querying TBL_PRODUCT_SYSTEMS..."
    PS_QUERY="SELECT COUNT(*) FROM TBL_PRODUCT_SYSTEMS WHERE LOWER(NAME) LIKE '%beer%' OR LOWER(NAME) LIKE '%brew%';"
    PS_COUNT_RAW=$(derby_query "$ACTIVE_DB" "$PS_QUERY")
    PS_COUNT=$(echo "$PS_COUNT_RAW" | grep -o "[0-9]*" | tail -1)
    
    if [ "${PS_COUNT:-0}" -ge 1 ]; then
        PRODUCT_SYSTEM_CREATED="true"
    fi

    # D. Check LCIA Methods
    LCIA_COUNT=$(derby_count "$ACTIVE_DB" "IMPACT_METHODS")
    if [ "${LCIA_COUNT:-0}" -gt 0 ]; then
        LCIA_METHODS_PRESENT="true"
    fi
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "has_gwp_keyword": $HAS_GWP,
    "process_created": $PROCESS_CREATED,
    "process_name_detected": "$NEW_PROCESS_NAME",
    "exchanges_defined": $EXCHANGES_DEFINED,
    "input_exchange_count": ${INPUT_COUNT:-0},
    "product_system_created": $PRODUCT_SYSTEM_CREATED,
    "lcia_methods_present": $LCIA_METHODS_PRESENT
}
EOF

# Move to public location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result export complete."
cat /tmp/task_result.json