#!/bin/bash
echo "=== Exporting order_lab_tests task result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot immediately
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final_state.png
if [ -f /tmp/task_final_state.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
    SCREENSHOT_EXISTS="true"
else
    echo "WARNING: Could not capture final screenshot"
    SCREENSHOT_EXISTS="false"
    SCREENSHOT_SIZE="0"
fi

# Target patient
PATIENT_PID=5

# Get task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Get initial counts from setup
INITIAL_ORDER_COUNT=$(cat /tmp/initial_order_count.txt 2>/dev/null || echo "0")
INITIAL_TOTAL_COUNT=$(cat /tmp/initial_total_order_count.txt 2>/dev/null || echo "0")
INITIAL_MAX_ID=$(cat /tmp/initial_max_order_id.txt 2>/dev/null || echo "0")

# Get current procedure order counts
CURRENT_ORDER_COUNT=$(openemr_query "SELECT COUNT(*) FROM procedure_order WHERE patient_id=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_TOTAL_COUNT=$(openemr_query "SELECT COUNT(*) FROM procedure_order" 2>/dev/null || echo "0")
CURRENT_MAX_ID=$(openemr_query "SELECT COALESCE(MAX(procedure_order_id), 0) FROM procedure_order" 2>/dev/null || echo "0")

echo ""
echo "=== Order Count Comparison ==="
echo "Patient orders: initial=$INITIAL_ORDER_COUNT, current=$CURRENT_ORDER_COUNT"
echo "Total orders: initial=$INITIAL_TOTAL_COUNT, current=$CURRENT_TOTAL_COUNT"
echo "Max order ID: initial=$INITIAL_MAX_ID, current=$CURRENT_MAX_ID"

# Determine if new order was created
NEW_ORDER_CREATED="false"
if [ "$CURRENT_ORDER_COUNT" -gt "$INITIAL_ORDER_COUNT" ]; then
    NEW_ORDER_CREATED="true"
    echo "NEW ORDER DETECTED for patient $PATIENT_PID"
elif [ "$CURRENT_MAX_ID" -gt "$INITIAL_MAX_ID" ]; then
    echo "New order detected but for different patient"
fi

# Query for new orders (orders with ID greater than initial max)
echo ""
echo "=== Querying New Orders ==="
NEW_ORDERS=$(openemr_query "SELECT procedure_order_id, patient_id, provider_id, date_ordered, order_priority, order_status, clinical_hx FROM procedure_order WHERE procedure_order_id > $INITIAL_MAX_ID ORDER BY procedure_order_id DESC" 2>/dev/null)
echo "New orders since task start:"
echo "$NEW_ORDERS"

# Query for the most recent order for our target patient
echo ""
echo "=== Latest Order for Patient $PATIENT_PID ==="
LATEST_ORDER=$(openemr_query "SELECT procedure_order_id, patient_id, provider_id, date_ordered, order_priority, order_status, clinical_hx FROM procedure_order WHERE patient_id=$PATIENT_PID ORDER BY procedure_order_id DESC LIMIT 1" 2>/dev/null)
echo "$LATEST_ORDER"

# Parse the latest order details
ORDER_ID=""
ORDER_PATIENT_ID=""
ORDER_PROVIDER=""
ORDER_DATE=""
ORDER_PRIORITY=""
ORDER_STATUS=""
ORDER_CLINICAL_HX=""

if [ -n "$LATEST_ORDER" ] && [ "$NEW_ORDER_CREATED" = "true" ]; then
    ORDER_ID=$(echo "$LATEST_ORDER" | cut -f1)
    ORDER_PATIENT_ID=$(echo "$LATEST_ORDER" | cut -f2)
    ORDER_PROVIDER=$(echo "$LATEST_ORDER" | cut -f3)
    ORDER_DATE=$(echo "$LATEST_ORDER" | cut -f4)
    ORDER_PRIORITY=$(echo "$LATEST_ORDER" | cut -f5)
    ORDER_STATUS=$(echo "$LATEST_ORDER" | cut -f6)
    ORDER_CLINICAL_HX=$(echo "$LATEST_ORDER" | cut -f7)
    
    echo ""
    echo "Parsed order details:"
    echo "  Order ID: $ORDER_ID"
    echo "  Patient ID: $ORDER_PATIENT_ID"
    echo "  Provider: $ORDER_PROVIDER"
    echo "  Date: $ORDER_DATE"
    echo "  Priority: $ORDER_PRIORITY"
    echo "  Status: $ORDER_STATUS"
    echo "  Clinical Hx: $ORDER_CLINICAL_HX"
fi

# Query procedure_order_code for test details
ORDER_CODES=""
PROCEDURE_CODE=""
PROCEDURE_NAME=""
PROCEDURE_DIAGNOSES=""
HAS_LIPID_TEST="false"

if [ -n "$ORDER_ID" ]; then
    echo ""
    echo "=== Procedure Order Codes for Order $ORDER_ID ==="
    ORDER_CODES=$(openemr_query "SELECT procedure_order_seq, procedure_code, procedure_name, diagnoses FROM procedure_order_code WHERE procedure_order_id=$ORDER_ID" 2>/dev/null)
    echo "$ORDER_CODES"
    
    if [ -n "$ORDER_CODES" ]; then
        PROCEDURE_CODE=$(echo "$ORDER_CODES" | head -1 | cut -f2)
        PROCEDURE_NAME=$(echo "$ORDER_CODES" | head -1 | cut -f3)
        PROCEDURE_DIAGNOSES=$(echo "$ORDER_CODES" | head -1 | cut -f4)
        
        # Check if it's a lipid-related test (case-insensitive)
        CODES_LOWER=$(echo "$ORDER_CODES" | tr '[:upper:]' '[:lower:]')
        if echo "$CODES_LOWER" | grep -qE "(lipid|cholesterol|ldl|hdl|triglyceride|cardiovascular)"; then
            HAS_LIPID_TEST="true"
            echo "LIPID-RELATED TEST DETECTED"
        fi
    fi
fi

# Check clinical history for relevant keywords
HAS_CLINICAL_NOTES="false"
CLINICAL_LOWER=$(echo "$ORDER_CLINICAL_HX $PROCEDURE_DIAGNOSES" | tr '[:upper:]' '[:lower:]')
if echo "$CLINICAL_LOWER" | grep -qE "(wellness|screen|cardiovascular|annual|preventive|lipid)"; then
    HAS_CLINICAL_NOTES="true"
    echo "APPROPRIATE CLINICAL NOTES DETECTED"
fi

# Check if order was created after task start
ORDER_CREATED_DURING_TASK="false"
if [ -n "$ORDER_ID" ] && [ "$ORDER_ID" -gt "$INITIAL_MAX_ID" ]; then
    ORDER_CREATED_DURING_TASK="true"
fi

# Escape strings for JSON
ORDER_CLINICAL_HX_ESCAPED=$(echo "$ORDER_CLINICAL_HX" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 500)
PROCEDURE_NAME_ESCAPED=$(echo "$PROCEDURE_NAME" | sed 's/"/\\"/g' | tr '\n' ' ')
PROCEDURE_DIAGNOSES_ESCAPED=$(echo "$PROCEDURE_DIAGNOSES" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/order_lab_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "patient_pid": $PATIENT_PID,
    "initial_order_count": ${INITIAL_ORDER_COUNT:-0},
    "current_order_count": ${CURRENT_ORDER_COUNT:-0},
    "initial_max_order_id": ${INITIAL_MAX_ID:-0},
    "current_max_order_id": ${CURRENT_MAX_ID:-0},
    "new_order_created": $NEW_ORDER_CREATED,
    "order_created_during_task": $ORDER_CREATED_DURING_TASK,
    "order": {
        "order_id": "${ORDER_ID:-}",
        "patient_id": "${ORDER_PATIENT_ID:-}",
        "provider_id": "${ORDER_PROVIDER:-}",
        "date_ordered": "${ORDER_DATE:-}",
        "priority": "${ORDER_PRIORITY:-}",
        "status": "${ORDER_STATUS:-}",
        "clinical_hx": "${ORDER_CLINICAL_HX_ESCAPED:-}"
    },
    "procedure_codes": {
        "code": "${PROCEDURE_CODE:-}",
        "name": "${PROCEDURE_NAME_ESCAPED:-}",
        "diagnoses": "${PROCEDURE_DIAGNOSES_ESCAPED:-}"
    },
    "validation": {
        "has_lipid_test": $HAS_LIPID_TEST,
        "has_clinical_notes": $HAS_CLINICAL_NOTES,
        "correct_patient": $([ "$ORDER_PATIENT_ID" = "$PATIENT_PID" ] && echo "true" || echo "false")
    },
    "screenshot": {
        "exists": $SCREENSHOT_EXISTS,
        "size_bytes": $SCREENSHOT_SIZE,
        "path": "/tmp/task_final_state.png"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Complete ==="
echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json