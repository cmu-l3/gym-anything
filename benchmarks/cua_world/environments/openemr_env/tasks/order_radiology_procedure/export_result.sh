#!/bin/bash
# Export script for Order Radiology Procedure Task
echo "=== Exporting Order Radiology Procedure Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=4

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    echo "Final screenshot captured"
else
    echo "WARNING: Could not capture final screenshot"
fi

# Get initial counts
INITIAL_PROC_COUNT=$(cat /tmp/initial_procedure_count.txt 2>/dev/null || echo "0")
INITIAL_BILLING_COUNT=$(cat /tmp/initial_billing_count.txt 2>/dev/null || echo "0")
INITIAL_FORMS_COUNT=$(cat /tmp/initial_forms_count.txt 2>/dev/null || echo "0")

echo ""
echo "Initial counts:"
echo "  Procedure orders: $INITIAL_PROC_COUNT"
echo "  Billing entries: $INITIAL_BILLING_COUNT"
echo "  Forms: $INITIAL_FORMS_COUNT"

# Get current procedure order count
CURRENT_PROC_COUNT=$(openemr_query "SELECT COUNT(*) FROM procedure_order WHERE patient_id=$PATIENT_PID" 2>/dev/null || echo "0")
echo "Current procedure order count: $CURRENT_PROC_COUNT"

# Get current billing count
CURRENT_BILLING_COUNT=$(openemr_query "SELECT COUNT(*) FROM billing WHERE pid=$PATIENT_PID AND code_type IN ('CPT4', 'HCPCS', 'CPT')" 2>/dev/null || echo "0")
echo "Current billing count: $CURRENT_BILLING_COUNT"

# Get current forms count
CURRENT_FORMS_COUNT=$(openemr_query "SELECT COUNT(*) FROM forms WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "Current forms count: $CURRENT_FORMS_COUNT"

# Check for new procedure orders
echo ""
echo "=== Checking for procedure orders ==="
PROC_ORDERS=$(openemr_query "SELECT procedure_order_id, patient_id, provider_id, date_ordered, order_priority, order_status, clinical_hx, order_diagnosis FROM procedure_order WHERE patient_id=$PATIENT_PID ORDER BY procedure_order_id DESC LIMIT 5" 2>/dev/null)
echo "Procedure orders for patient:"
echo "$PROC_ORDERS"

# Check procedure_order_code table for procedure details
echo ""
echo "=== Checking procedure codes ==="
PROC_CODES=$(openemr_query "SELECT poc.procedure_order_id, poc.procedure_code, poc.procedure_name, poc.diagnoses FROM procedure_order po JOIN procedure_order_code poc ON po.procedure_order_id = poc.procedure_order_id WHERE po.patient_id=$PATIENT_PID ORDER BY po.procedure_order_id DESC LIMIT 10" 2>/dev/null)
echo "Procedure codes for patient orders:"
echo "$PROC_CODES"

# Check billing table for CPT codes
echo ""
echo "=== Checking billing entries ==="
BILLING_ENTRIES=$(openemr_query "SELECT id, pid, encounter, code_type, code, modifier, units, fee, justify, activity FROM billing WHERE pid=$PATIENT_PID AND code_type IN ('CPT4', 'HCPCS', 'CPT') ORDER BY id DESC LIMIT 10" 2>/dev/null)
echo "Billing entries for patient:"
echo "$BILLING_ENTRIES"

# Check fee sheet (forms table)
echo ""
echo "=== Checking forms/fee sheets ==="
FORMS_ENTRIES=$(openemr_query "SELECT id, encounter, form_name, formdir FROM forms WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 10" 2>/dev/null)
echo "Forms for patient:"
echo "$FORMS_ENTRIES"

# Get the newest procedure order details
NEWEST_PROC_ORDER=""
PROC_ORDER_FOUND="false"
PROC_ORDER_ID=""
PROC_ORDER_DATE=""
PROC_ORDER_PRIORITY=""
PROC_ORDER_STATUS=""
PROC_ORDER_CLINICAL_HX=""
PROC_ORDER_DIAGNOSIS=""

if [ "$CURRENT_PROC_COUNT" -gt "$INITIAL_PROC_COUNT" ]; then
    PROC_ORDER_FOUND="true"
    NEWEST_PROC_ORDER=$(openemr_query "SELECT procedure_order_id, date_ordered, order_priority, order_status, clinical_hx, order_diagnosis FROM procedure_order WHERE patient_id=$PATIENT_PID ORDER BY procedure_order_id DESC LIMIT 1" 2>/dev/null)
    
    if [ -n "$NEWEST_PROC_ORDER" ]; then
        PROC_ORDER_ID=$(echo "$NEWEST_PROC_ORDER" | cut -f1)
        PROC_ORDER_DATE=$(echo "$NEWEST_PROC_ORDER" | cut -f2)
        PROC_ORDER_PRIORITY=$(echo "$NEWEST_PROC_ORDER" | cut -f3)
        PROC_ORDER_STATUS=$(echo "$NEWEST_PROC_ORDER" | cut -f4)
        PROC_ORDER_CLINICAL_HX=$(echo "$NEWEST_PROC_ORDER" | cut -f5)
        PROC_ORDER_DIAGNOSIS=$(echo "$NEWEST_PROC_ORDER" | cut -f6)
        
        echo ""
        echo "Newest procedure order found:"
        echo "  ID: $PROC_ORDER_ID"
        echo "  Date: $PROC_ORDER_DATE"
        echo "  Priority: $PROC_ORDER_PRIORITY"
        echo "  Status: $PROC_ORDER_STATUS"
        echo "  Clinical History: $PROC_ORDER_CLINICAL_HX"
        echo "  Diagnosis: $PROC_ORDER_DIAGNOSIS"
    fi
fi

# Check for chest x-ray related entries in billing
BILLING_ORDER_FOUND="false"
BILLING_CODE=""
BILLING_JUSTIFY=""

# Chest X-Ray CPT codes: 71045, 71046, 71047, 71048
XRAY_CODES="71045|71046|71047|71048|71100|71101|71110|71111"
if [ "$CURRENT_BILLING_COUNT" -gt "$INITIAL_BILLING_COUNT" ]; then
    BILLING_ORDER_FOUND="true"
    NEWEST_BILLING=$(openemr_query "SELECT id, code, justify FROM billing WHERE pid=$PATIENT_PID AND code_type IN ('CPT4', 'HCPCS', 'CPT') ORDER BY id DESC LIMIT 1" 2>/dev/null)
    
    if [ -n "$NEWEST_BILLING" ]; then
        BILLING_CODE=$(echo "$NEWEST_BILLING" | cut -f2)
        BILLING_JUSTIFY=$(echo "$NEWEST_BILLING" | cut -f3)
        echo ""
        echo "Newest billing entry:"
        echo "  Code: $BILLING_CODE"
        echo "  Justify: $BILLING_JUSTIFY"
    fi
fi

# Check if any order mentions chest x-ray
CHEST_XRAY_FOUND="false"
ALL_PROC_TEXT=$(echo "$PROC_ORDERS $PROC_CODES" | tr '[:upper:]' '[:lower:]')
ALL_BILLING_TEXT=$(echo "$BILLING_ENTRIES" | tr '[:upper:]' '[:lower:]')

if echo "$ALL_PROC_TEXT" | grep -qiE "(chest|x-ray|xray|radiograph|cxr|71046|71047|71045|71048)"; then
    CHEST_XRAY_FOUND="true"
    echo "Chest X-Ray related content found in procedure orders"
fi

if echo "$ALL_BILLING_TEXT" | grep -qE "$XRAY_CODES"; then
    CHEST_XRAY_FOUND="true"
    echo "Chest X-Ray CPT code found in billing"
fi

# Check for clinical indication keywords
CLINICAL_INDICATION_FOUND="false"
CLINICAL_TEXT="$PROC_ORDER_CLINICAL_HX $PROC_ORDER_DIAGNOSIS $BILLING_JUSTIFY"
CLINICAL_TEXT_LOWER=$(echo "$CLINICAL_TEXT" | tr '[:upper:]' '[:lower:]')

if echo "$CLINICAL_TEXT_LOWER" | grep -qiE "(pneumonia|cough|fever|dyspnea|respiratory|chest|lung|shortness|breath)"; then
    CLINICAL_INDICATION_FOUND="true"
    echo "Clinical indication keywords found"
fi

# Escape special characters for JSON
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/\t/ /g' | tr '\n' ' ' | sed 's/  */ /g'
}

PROC_ORDER_CLINICAL_HX_ESC=$(escape_json "$PROC_ORDER_CLINICAL_HX")
PROC_ORDER_DIAGNOSIS_ESC=$(escape_json "$PROC_ORDER_DIAGNOSIS")
BILLING_JUSTIFY_ESC=$(escape_json "$BILLING_JUSTIFY")
PROC_CODES_ESC=$(escape_json "$PROC_CODES")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/radiology_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_counts": {
        "procedure_orders": $INITIAL_PROC_COUNT,
        "billing_entries": $INITIAL_BILLING_COUNT,
        "forms": $INITIAL_FORMS_COUNT
    },
    "current_counts": {
        "procedure_orders": $CURRENT_PROC_COUNT,
        "billing_entries": $CURRENT_BILLING_COUNT,
        "forms": $CURRENT_FORMS_COUNT
    },
    "procedure_order": {
        "found": $PROC_ORDER_FOUND,
        "id": "$PROC_ORDER_ID",
        "date": "$PROC_ORDER_DATE",
        "priority": "$PROC_ORDER_PRIORITY",
        "status": "$PROC_ORDER_STATUS",
        "clinical_hx": "$PROC_ORDER_CLINICAL_HX_ESC",
        "diagnosis": "$PROC_ORDER_DIAGNOSIS_ESC"
    },
    "billing_order": {
        "found": $BILLING_ORDER_FOUND,
        "code": "$BILLING_CODE",
        "justify": "$BILLING_JUSTIFY_ESC"
    },
    "validation": {
        "new_order_created": $([ "$CURRENT_PROC_COUNT" -gt "$INITIAL_PROC_COUNT" ] || [ "$CURRENT_BILLING_COUNT" -gt "$INITIAL_BILLING_COUNT" ] && echo "true" || echo "false"),
        "chest_xray_found": $CHEST_XRAY_FOUND,
        "clinical_indication_found": $CLINICAL_INDICATION_FOUND
    },
    "procedure_codes_raw": "$PROC_CODES_ESC",
    "screenshot_path": "/tmp/task_final_state.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/radiology_order_result.json 2>/dev/null || sudo rm -f /tmp/radiology_order_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/radiology_order_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/radiology_order_result.json
chmod 666 /tmp/radiology_order_result.json 2>/dev/null || sudo chmod 666 /tmp/radiology_order_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/radiology_order_result.json
echo ""
echo "=== Export Complete ==="