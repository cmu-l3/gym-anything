#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Material Impact Claim Verification Result ==="

# 1. Capture final state
take_screenshot /tmp/task_final_screenshot.png
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
NOW=$(date +%s)

# 2. Analyze Output File
OUTPUT_FILE="/home/ga/LCA_Results/claim_verification.txt"
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_CREATED_DURING_TASK="false"
PARSED_VALUE=""
VERDICT_FOUND=""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    # Check modification time
    FMTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FMTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content (limit size)
    FILE_CONTENT=$(head -c 500 "$OUTPUT_FILE")
    
    # Try to extract numbers and keywords using regex
    PARSED_VALUE=$(echo "$FILE_CONTENT" | grep -oP "[0-9]+(\.[0-9]+)?" | head -1 || echo "")
    
    if echo "$FILE_CONTENT" | grep -qi "REJECTED"; then
        VERDICT_FOUND="REJECTED"
    elif echo "$FILE_CONTENT" | grep -qi "CONFIRMED"; then
        VERDICT_FOUND="CONFIRMED"
    fi
fi

# 3. Check OpenLCA Application State (Logs & DB)
# Check logs for calculation evidence
LOG_FILE="/tmp/openlca_ga.log"
CALCULATION_RUN="false"
LCIA_METHOD_USED="false"

if [ -f "$LOG_FILE" ]; then
    if grep -qi "calculat\|LCIA\|impact" "$LOG_FILE"; then
        CALCULATION_RUN="true"
    fi
    if grep -qi "TRACI" "$LOG_FILE"; then
        LCIA_METHOD_USED="true"
    fi
fi

# Close app to inspect DB safely
close_openlca
sleep 3

# Check DB for Product Systems (evidence of modeling)
DB_DIR="/home/ga/openLCA-data-1.4/databases"
PRODUCT_SYSTEM_COUNT=0
IMPACT_CATEGORY_COUNT=0
DB_FOUND="false"

# Find the active database (largest one modified recently)
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

if [ -n "$ACTIVE_DB" ] && [ "$MAX_SIZE" -gt 5 ]; then
    DB_FOUND="true"
    PRODUCT_SYSTEM_COUNT=$(derby_count "$ACTIVE_DB" "PRODUCT_SYSTEMS" 2>/dev/null || echo "0")
    IMPACT_CATEGORY_COUNT=$(derby_count "$ACTIVE_DB" "IMPACT_CATEGORIES" 2>/dev/null || echo "0")
fi

# 4. JSON Export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_content_snippet": "$(echo "$FILE_CONTENT" | tr -d '\n' | sed 's/"/\\"/g')",
    "parsed_value": "$PARSED_VALUE",
    "verdict_found": "$VERDICT_FOUND",
    "calculation_run": $CALCULATION_RUN,
    "lcia_method_used": $LCIA_METHOD_USED,
    "db_found": $DB_FOUND,
    "product_system_count": ${PRODUCT_SYSTEM_COUNT:-0},
    "impact_category_count": ${IMPACT_CATEGORY_COUNT:-0},
    "screenshot_path": "/tmp/task_final_screenshot.png",
    "timestamp": "$NOW"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="