#!/bin/bash
# Export script for Custom LCIA Water Scarcity task
# Post-task hook: runs AFTER the agent finishes

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

echo "=== Exporting Custom LCIA Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png
echo "Final screenshot saved"

# 2. Check for result CSV file
RESULTS_DIR="/home/ga/LCA_Results"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
RESULT_FILE=""
RESULT_FILE_SIZE=0
RESULT_HAS_CONTENT="false"
RESULT_HAS_KEYWORD="false"
FILE_CREATED_DURING_TASK="false"

# Look for specifically named file first, then any relevant CSV
TARGET_FILE="$RESULTS_DIR/water_scarcity_result.csv"

if [ -f "$TARGET_FILE" ]; then
    RESULT_FILE="$TARGET_FILE"
else
    # Fallback search
    RESULT_FILE=$(find "$RESULTS_DIR" -name "*water*.csv" -o -name "*scarcity*.csv" | head -n 1)
fi

if [ -n "$RESULT_FILE" ] && [ -f "$RESULT_FILE" ]; then
    RESULT_FILE_SIZE=$(stat -c %s "$RESULT_FILE" 2>/dev/null || echo "0")
    FMTIME=$(stat -c %Y "$RESULT_FILE" 2>/dev/null || echo "0")
    
    if [ "$((FMTIME))" -gt "$((TASK_START))" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Check content
    if [ "$RESULT_FILE_SIZE" -gt 20 ]; then
        # Check for numeric values (basic regex for CSV numbers)
        if grep -qE "[0-9]+\.[0-9]+" "$RESULT_FILE"; then
            RESULT_HAS_CONTENT="true"
        fi
        # Check for task keywords
        if grep -qi "water\|scarcity\|regional\|m3" "$RESULT_FILE"; then
            RESULT_HAS_KEYWORD="true"
        fi
    fi
fi

# 3. Verify Database State (Method creation)
# Close OpenLCA to query Derby
close_openlca
sleep 4

DB_DIR="/home/ga/openLCA-data-1.4/databases"
METHOD_FOUND="false"
CATEGORY_FOUND="false"
FACTORS_COUNT=0
DB_FOUND="false"
ACTIVE_DB_PATH=""

# Find the most likely active database (largest or most recent)
MAX_SIZE=0
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    DB_SIZE=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${DB_SIZE:-0}" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="${DB_SIZE:-0}"
        ACTIVE_DB_PATH="$db_path"
    fi
done

if [ -n "$ACTIVE_DB_PATH" ] && [ "${MAX_SIZE:-0}" -gt 5 ]; then
    DB_FOUND="true"
    echo "Checking database: $(basename "$ACTIVE_DB_PATH")"

    # Query 1: Check if Method exists
    # SQL: Select name from TBL_IMPACT_METHODS where name like '%Water Scarcity%'
    METHOD_QUERY="SELECT NAME, ID FROM TBL_IMPACT_METHODS WHERE LOWER(NAME) LIKE '%water scarcity%' OR LOWER(NAME) LIKE '%regional water%'"
    METHOD_RES=$(derby_query "$ACTIVE_DB_PATH" "$METHOD_QUERY" 2>/dev/null)
    
    if echo "$METHOD_RES" | grep -qi "water"; then
        METHOD_FOUND="true"
        echo "  Method found."
        
        # Query 2: Check Category
        # We need the Method ID to be precise, but simpler is just checking Categories generally
        CAT_QUERY="SELECT NAME FROM TBL_IMPACT_CATEGORIES WHERE LOWER(NAME) LIKE '%water scarcity%' AND LOWER(REF_UNIT) LIKE '%m3%'"
        CAT_RES=$(derby_query "$ACTIVE_DB_PATH" "$CAT_QUERY" 2>/dev/null)
        
        if echo "$CAT_RES" | grep -qi "water"; then
            CATEGORY_FOUND="true"
            echo "  Category found."
            
            # Query 3: Count Factors
            # Complex join to count factors for categories matching the name
            # TBL_IMPACT_FACTORS linked to TBL_IMPACT_CATEGORIES
            FACTOR_QUERY="SELECT COUNT(*) FROM TBL_IMPACT_FACTORS f JOIN TBL_IMPACT_CATEGORIES c ON f.IMPACT_CATEGORY_ID = c.ID WHERE LOWER(c.NAME) LIKE '%water scarcity%'"
            FACTORS_RES=$(derby_query "$ACTIVE_DB_PATH" "$FACTOR_QUERY" 2>/dev/null)
            
            # Extract number from ij output (format usually: "1 row selected\n <NUMBER>")
            FACTORS_COUNT=$(echo "$FACTORS_RES" | grep -oP '^\s*\K\d+' | tail -1 || echo "0")
            echo "  Factors count: $FACTORS_COUNT"
        fi
    fi
fi

# 4. JSON Output
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "db_found": $DB_FOUND,
    "method_found": $METHOD_FOUND,
    "category_found": $CATEGORY_FOUND,
    "factors_count": ${FACTORS_COUNT:-0},
    "result_file_exists": $([ -n "$RESULT_FILE" ] && echo "true" || echo "false"),
    "result_file_created_during_task": $FILE_CREATED_DURING_TASK,
    "result_has_content": $RESULT_HAS_CONTENT,
    "result_has_keyword": $RESULT_HAS_KEYWORD,
    "result_file_size": $RESULT_FILE_SIZE,
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json