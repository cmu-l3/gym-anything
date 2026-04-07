#!/bin/bash
echo "=== Exporting Create and Invoice Service Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# -----------------------------------------------------------------------------
# 1. Verify Service Creation
# -----------------------------------------------------------------------------
echo "Checking for service TELE01..."
SERVICE_JSON=$(clinical_query "SELECT CONCAT('{\"found\":true, \"uid\":\"', OC_PRESTATION_OBJECTID, '\", \"code\":\"', OC_PRESTATION_CODE, '\", \"price\":', OC_PRESTATION_PRICE, '}') FROM oc_prestations WHERE OC_PRESTATION_CODE='TELE01' LIMIT 1")

if [ -z "$SERVICE_JSON" ]; then
    SERVICE_JSON="{\"found\":false}"
fi

# Extract Service UID for next checks
SERVICE_UID=$(echo "$SERVICE_JSON" | grep -o 'uid":"[^"]*' | cut -d'"' -f3)

# -----------------------------------------------------------------------------
# 2. Verify Charge (Debet) Recording
# -----------------------------------------------------------------------------
CHARGE_FOUND="false"
CHARGE_INVOICED="false"
INVOICE_UID=""

if [ -n "$SERVICE_UID" ]; then
    echo "Checking for charges for service ID $SERVICE_UID..."
    # Check debets for patient 10004 with this service
    # OC_DEBET_PATIENTINVOICEUID is usually populated when invoiced (not -1 or NULL)
    DEBET_ROW=$(clinical_query "SELECT OC_DEBET_OBJECTID, OC_DEBET_PATIENTINVOICEUID FROM oc_debets WHERE OC_DEBET_PATIENTID=10004 AND OC_DEBET_PRESTATIONUID='$SERVICE_UID' ORDER BY OC_DEBET_DATE DESC LIMIT 1")
    
    if [ -n "$DEBET_ROW" ]; then
        CHARGE_FOUND="true"
        INVOICE_UID=$(echo "$DEBET_ROW" | cut -f2)
        
        # Check if Invoice UID is valid (some systems use -1 or empty for null)
        if [ -n "$INVOICE_UID" ] && [ "$INVOICE_UID" != "-1" ] && [ "$INVOICE_UID" != "NULL" ]; then
            CHARGE_INVOICED="true"
        else
            INVOICE_UID=""
        fi
    fi
fi

# -----------------------------------------------------------------------------
# 3. Verify Invoice Existence
# -----------------------------------------------------------------------------
INVOICE_FOUND="false"
INVOICE_TIMESTAMP=""

if [ -n "$INVOICE_UID" ]; then
    echo "Checking invoice ID $INVOICE_UID..."
    INVOICE_DATE=$(clinical_query "SELECT OC_PATIENTINVOICE_UPDATETIME FROM oc_patientinvoices WHERE OC_PATIENTINVOICE_OBJECTID='$INVOICE_UID'")
    if [ -n "$INVOICE_DATE" ]; then
        INVOICE_FOUND="true"
        INVOICE_TIMESTAMP="$INVOICE_DATE"
    fi
fi

# Anti-gaming: Check if invoice is new (created after task start)
# We can compare timestamps in python, just passing the string here.

# -----------------------------------------------------------------------------
# 4. Construct Result JSON
# -----------------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "service": $SERVICE_JSON,
    "charge": {
        "found": $CHARGE_FOUND,
        "invoiced": $CHARGE_INVOICED,
        "invoice_uid": "$INVOICE_UID"
    },
    "invoice": {
        "found": $INVOICE_FOUND,
        "timestamp": "$INVOICE_TIMESTAMP"
    },
    "task_start_timestamp": $(cat /tmp/task_start_timestamp 2>/dev/null || echo "0"),
    "export_timestamp": $(date +%s)
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="