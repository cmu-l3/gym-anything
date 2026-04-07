#!/bin/bash
# Export script for Shadow Carbon Pricing Method task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Shadow Carbon Pricing Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Task timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/LCA_Results"
OUTPUT_FILE="$RESULTS_DIR/truck_carbon_liability.csv"

# 1. Check Output File
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
HAS_CATEGORY_NAME="false"
HAS_NUMERIC_VALUES="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FMTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$((FMTIME))" -gt "$((TASK_START))" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Check content
    if grep -qi "Carbon Liability" "$OUTPUT_FILE"; then
        HAS_CATEGORY_NAME="true"
    fi
    # Check for non-zero numbers
    if grep -E "[0-9]+\.[0-9]+" "$OUTPUT_FILE" | grep -v "0.00000" > /dev/null; then
        HAS_NUMERIC_VALUES="true"
    fi
fi

# 2. Database Verification (Derby Queries)
# We need to query the DB to verify the method structure
close_openlca
sleep 3

DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_SIZE=0
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    current_size=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${current_size:-0}" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="${current_size:-0}"
        ACTIVE_DB="$db_path"
    fi
done

METHOD_EXISTS="false"
CATEGORY_EXISTS="false"
FACTOR_CO2_OK="false"
FACTOR_CH4_OK="false"
FACTOR_NOX_OK="false"

if [ -n "$ACTIVE_DB" ]; then
    echo "Querying database: $ACTIVE_DB"

    # Check Method Name
    METHOD_CHECK=$(derby_query "$ACTIVE_DB" "SELECT NAME FROM TBL_IMPACT_METHODS WHERE NAME LIKE '%Shadow Carbon Price 2026%';" 2>/dev/null)
    if echo "$METHOD_CHECK" | grep -q "Shadow Carbon Price 2026"; then
        METHOD_EXISTS="true"
    fi

    # Check Category Name
    CAT_CHECK=$(derby_query "$ACTIVE_DB" "SELECT NAME FROM TBL_IMPACT_CATEGORIES WHERE NAME LIKE '%Carbon Liability%';" 2>/dev/null)
    if echo "$CAT_CHECK" | grep -q "Carbon Liability"; then
        CATEGORY_EXISTS="true"
    fi

    # Check CO2 Factor (0.10)
    # Join factors to flows to verify the value for CO2
    CO2_CHECK=$(derby_query "$ACTIVE_DB" "SELECT count(*) FROM TBL_IMPACT_FACTORS f JOIN TBL_FLOWS fl ON f.F_FLOW = fl.ID WHERE (fl.NAME LIKE '%Carbon dioxide%' OR fl.NAME LIKE '%CO2%') AND f.VALUE > 0.09 AND f.VALUE < 0.11;" 2>/dev/null)
    # derby_query returns dirty output, extract number
    CO2_COUNT=$(echo "$CO2_CHECK" | grep -oP '^\s*\K\d+' | head -1 || echo "0")
    if [ "$CO2_COUNT" -ge 1 ]; then
        FACTOR_CO2_OK="true"
    fi

    # Check Methane Factor (2.80)
    CH4_CHECK=$(derby_query "$ACTIVE_DB" "SELECT count(*) FROM TBL_IMPACT_FACTORS f JOIN TBL_FLOWS fl ON f.F_FLOW = fl.ID WHERE (fl.NAME LIKE '%Methane%' OR fl.NAME LIKE '%CH4%') AND f.VALUE > 2.79 AND f.VALUE < 2.81;" 2>/dev/null)
    CH4_COUNT=$(echo "$CH4_CHECK" | grep -oP '^\s*\K\d+' | head -1 || echo "0")
    if [ "$CH4_COUNT" -ge 1 ]; then
        FACTOR_CH4_OK="true"
    fi

    # Check NOx Factor (0.50)
    NOX_CHECK=$(derby_query "$ACTIVE_DB" "SELECT count(*) FROM TBL_IMPACT_FACTORS f JOIN TBL_FLOWS fl ON f.F_FLOW = fl.ID WHERE (fl.NAME LIKE '%Nitrogen oxides%' OR fl.NAME LIKE '%NOx%') AND f.VALUE > 0.49 AND f.VALUE < 0.51;" 2>/dev/null)
    NOX_COUNT=$(echo "$NOX_CHECK" | grep -oP '^\s*\K\d+' | head -1 || echo "0")
    if [ "$NOX_COUNT" -ge 1 ]; then
        FACTOR_NOX_OK="true"
    fi
fi

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "has_category_name": $HAS_CATEGORY_NAME,
    "has_numeric_values": $HAS_NUMERIC_VALUES,
    "db_found": $([ -n "$ACTIVE_DB" ] && echo "true" || echo "false"),
    "method_exists": $METHOD_EXISTS,
    "category_exists": $CATEGORY_EXISTS,
    "factor_co2_ok": $FACTOR_CO2_OK,
    "factor_ch4_ok": $FACTOR_CH4_OK,
    "factor_nox_ok": $FACTOR_NOX_OK
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json