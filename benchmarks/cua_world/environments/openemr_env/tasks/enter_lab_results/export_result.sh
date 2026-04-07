#!/bin/bash
# Export script for Enter Lab Results task

echo "=== Exporting Enter Lab Results Task Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png
echo "Final screenshot saved to /tmp/task_final.png"

# Target patient
PATIENT_PID=3

# Get initial counts
INITIAL_ORDER_COUNT=$(cat /tmp/initial_procedure_order_count 2>/dev/null || echo "0")
INITIAL_RESULT_COUNT=$(cat /tmp/initial_procedure_result_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_DATE=$(cat /tmp/task_date 2>/dev/null || date +%Y-%m-%d)

# Get current procedure order count for patient
CURRENT_ORDER_COUNT=$(openemr_query "SELECT COUNT(*) FROM procedure_order WHERE patient_id=$PATIENT_PID" 2>/dev/null || echo "0")

# Get current total procedure result count
CURRENT_RESULT_COUNT=$(openemr_query "SELECT COUNT(*) FROM procedure_result" 2>/dev/null || echo "0")

echo "Procedure order count: initial=$INITIAL_ORDER_COUNT, current=$CURRENT_ORDER_COUNT"
echo "Procedure result count: initial=$INITIAL_RESULT_COUNT, current=$CURRENT_RESULT_COUNT"

# Query for procedure orders for this patient (most recent first)
echo ""
echo "=== Querying procedure orders for patient PID=$PATIENT_PID ==="
ALL_ORDERS=$(openemr_query "SELECT procedure_order_id, date_ordered, order_status, provider_id FROM procedure_order WHERE patient_id=$PATIENT_PID ORDER BY procedure_order_id DESC LIMIT 5" 2>/dev/null)
echo "Recent procedure orders for patient:"
echo "$ALL_ORDERS"

# Get the most recent procedure order for this patient
NEWEST_ORDER=$(openemr_query "SELECT procedure_order_id, date_ordered, order_status FROM procedure_order WHERE patient_id=$PATIENT_PID ORDER BY procedure_order_id DESC LIMIT 1" 2>/dev/null)

ORDER_FOUND="false"
ORDER_ID=""
ORDER_DATE=""
ORDER_STATUS=""

if [ -n "$NEWEST_ORDER" ]; then
    ORDER_FOUND="true"
    ORDER_ID=$(echo "$NEWEST_ORDER" | cut -f1)
    ORDER_DATE=$(echo "$NEWEST_ORDER" | cut -f2)
    ORDER_STATUS=$(echo "$NEWEST_ORDER" | cut -f3)
    echo ""
    echo "Most recent order: ID=$ORDER_ID, Date=$ORDER_DATE, Status=$ORDER_STATUS"
fi

# Query for procedure results associated with this patient's orders
echo ""
echo "=== Querying procedure results ==="

# First get all procedure_report entries for this patient's orders
REPORTS=$(openemr_query "SELECT pr.procedure_report_id, pr.procedure_order_id, pr.date_report, pr.report_status FROM procedure_report pr JOIN procedure_order po ON pr.procedure_order_id = po.procedure_order_id WHERE po.patient_id=$PATIENT_PID ORDER BY pr.procedure_report_id DESC LIMIT 10" 2>/dev/null)
echo "Procedure reports for patient:"
echo "$REPORTS"

# Get actual result values
RESULTS=$(openemr_query "SELECT pres.procedure_result_id, pres.result_code, pres.result_text, pres.result, pres.units, pres.range, prep.procedure_order_id FROM procedure_result pres JOIN procedure_report prep ON pres.procedure_report_id = prep.procedure_report_id JOIN procedure_order po ON prep.procedure_order_id = po.procedure_order_id WHERE po.patient_id=$PATIENT_PID ORDER BY pres.procedure_result_id DESC LIMIT 20" 2>/dev/null)

echo ""
echo "Procedure results for patient:"
echo "$RESULTS"

# Parse results to check for expected lab values
RESULTS_FOUND="false"
GLUCOSE_VALUE=""
BUN_VALUE=""
CREATININE_VALUE=""
SODIUM_VALUE=""
POTASSIUM_VALUE=""
CHLORIDE_VALUE=""
CO2_VALUE=""
RESULTS_COUNT=0

if [ -n "$RESULTS" ]; then
    RESULTS_FOUND="true"
    
    # Count results
    RESULTS_COUNT=$(echo "$RESULTS" | grep -c "^" || echo "0")
    
    # Try to extract specific values by searching result_text or result_code
    # Glucose
    GLUCOSE_LINE=$(echo "$RESULTS" | grep -i "glucose" | head -1)
    if [ -n "$GLUCOSE_LINE" ]; then
        GLUCOSE_VALUE=$(echo "$GLUCOSE_LINE" | cut -f4)
    fi
    
    # BUN
    BUN_LINE=$(echo "$RESULTS" | grep -i "bun\|urea" | head -1)
    if [ -n "$BUN_LINE" ]; then
        BUN_VALUE=$(echo "$BUN_LINE" | cut -f4)
    fi
    
    # Creatinine
    CREAT_LINE=$(echo "$RESULTS" | grep -i "creatinine" | head -1)
    if [ -n "$CREAT_LINE" ]; then
        CREATININE_VALUE=$(echo "$CREAT_LINE" | cut -f4)
    fi
    
    # Sodium
    SODIUM_LINE=$(echo "$RESULTS" | grep -i "sodium\|^na\b" | head -1)
    if [ -n "$SODIUM_LINE" ]; then
        SODIUM_VALUE=$(echo "$SODIUM_LINE" | cut -f4)
    fi
    
    # Potassium
    POTASSIUM_LINE=$(echo "$RESULTS" | grep -i "potassium\|^k\b" | head -1)
    if [ -n "$POTASSIUM_LINE" ]; then
        POTASSIUM_VALUE=$(echo "$POTASSIUM_LINE" | cut -f4)
    fi
    
    # Chloride
    CHLORIDE_LINE=$(echo "$RESULTS" | grep -i "chloride\|^cl\b" | head -1)
    if [ -n "$CHLORIDE_LINE" ]; then
        CHLORIDE_VALUE=$(echo "$CHLORIDE_LINE" | cut -f4)
    fi
    
    # CO2/Bicarbonate
    CO2_LINE=$(echo "$RESULTS" | grep -i "co2\|bicarbonate\|hco3" | head -1)
    if [ -n "$CO2_LINE" ]; then
        CO2_VALUE=$(echo "$CO2_LINE" | cut -f4)
    fi
    
    echo ""
    echo "Extracted values:"
    echo "  Glucose: $GLUCOSE_VALUE"
    echo "  BUN: $BUN_VALUE"
    echo "  Creatinine: $CREATININE_VALUE"
    echo "  Sodium: $SODIUM_VALUE"
    echo "  Potassium: $POTASSIUM_VALUE"
    echo "  Chloride: $CHLORIDE_VALUE"
    echo "  CO2: $CO2_VALUE"
fi

# Check if new results were added during task
NEW_ORDER_CREATED="false"
if [ "$CURRENT_ORDER_COUNT" -gt "$INITIAL_ORDER_COUNT" ]; then
    NEW_ORDER_CREATED="true"
    echo "New procedure order was created"
fi

NEW_RESULTS_ADDED="false"
if [ "$CURRENT_RESULT_COUNT" -gt "$INITIAL_RESULT_COUNT" ]; then
    NEW_RESULTS_ADDED="true"
    NEW_RESULTS_NUM=$((CURRENT_RESULT_COUNT - INITIAL_RESULT_COUNT))
    echo "$NEW_RESULTS_NUM new result(s) were added"
fi

# Also check for any results in forms or other tables
# Some OpenEMR versions may store lab results differently
echo ""
echo "=== Checking alternative result storage ==="
FORM_RESULTS=$(openemr_query "SELECT id, date, pid FROM forms WHERE pid=$PATIENT_PID AND form_name LIKE '%lab%' ORDER BY id DESC LIMIT 5" 2>/dev/null || echo "")
echo "Form entries for patient:"
echo "$FORM_RESULTS"

# Record task end time
TASK_END=$(date +%s)

# Create result JSON
TEMP_JSON=$(mktemp /tmp/lab_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "task_date": "$TASK_DATE",
    "procedure_orders": {
        "initial_count": ${INITIAL_ORDER_COUNT:-0},
        "current_count": ${CURRENT_ORDER_COUNT:-0},
        "new_order_created": $NEW_ORDER_CREATED,
        "latest_order_id": "$ORDER_ID",
        "latest_order_date": "$ORDER_DATE",
        "latest_order_status": "$ORDER_STATUS"
    },
    "procedure_results": {
        "initial_count": ${INITIAL_RESULT_COUNT:-0},
        "current_count": ${CURRENT_RESULT_COUNT:-0},
        "new_results_added": $NEW_RESULTS_ADDED,
        "results_found_for_patient": $RESULTS_FOUND,
        "results_count": $RESULTS_COUNT
    },
    "lab_values": {
        "glucose": "$GLUCOSE_VALUE",
        "bun": "$BUN_VALUE",
        "creatinine": "$CREATININE_VALUE",
        "sodium": "$SODIUM_VALUE",
        "potassium": "$POTASSIUM_VALUE",
        "chloride": "$CHLORIDE_VALUE",
        "co2": "$CO2_VALUE"
    },
    "raw_results": $(echo "$RESULTS" | head -20 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""'),
    "screenshot_path": "/tmp/task_final.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move temp file to final location
rm -f /tmp/enter_lab_results_result.json 2>/dev/null || sudo rm -f /tmp/enter_lab_results_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/enter_lab_results_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/enter_lab_results_result.json
chmod 666 /tmp/enter_lab_results_result.json 2>/dev/null || sudo chmod 666 /tmp/enter_lab_results_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/enter_lab_results_result.json"
cat /tmp/enter_lab_results_result.json

echo ""
echo "=== Export Complete ==="