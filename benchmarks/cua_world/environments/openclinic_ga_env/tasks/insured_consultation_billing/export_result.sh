#!/bin/bash
echo "=== Exporting Insured Consultation Billing Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final_screenshot.png

PATIENT_ID=10002

# =========================================================================
# 1. Check for insurer (oc_insurars in openclinic_dbo)
# =========================================================================
echo "Checking for insurer..."

INSURAR_OID=$(clinical_query "SELECT OC_INSURAR_OBJECTID FROM oc_insurars WHERE OC_INSURAR_NAME LIKE '%MediShield%' ORDER BY OC_INSURAR_OBJECTID DESC LIMIT 1" 2>/dev/null | head -1 | tr -d '[:space:]')
INSURAR_NAME=""
INSURAR_LANG=""

if [ -n "$INSURAR_OID" ]; then
    INSURAR_NAME=$(clinical_query "SELECT OC_INSURAR_NAME FROM oc_insurars WHERE OC_INSURAR_OBJECTID='$INSURAR_OID'" 2>/dev/null | head -1)
    INSURAR_LANG=$(clinical_query "SELECT OC_INSURAR_LANGUAGE FROM oc_insurars WHERE OC_INSURAR_OBJECTID='$INSURAR_OID'" 2>/dev/null | head -1 | tr -d '[:space:]')
fi

INSURAR_FOUND="false"
[ -n "$INSURAR_OID" ] && INSURAR_FOUND="true"
# UID format for cross-table refs
INSURAR_UID="1.$INSURAR_OID"

echo "Insurer: found=$INSURAR_FOUND oid=$INSURAR_OID name=$INSURAR_NAME lang=$INSURAR_LANG"

# =========================================================================
# 2. Check insurance assignment for patient (oc_insurances in openclinic_dbo)
# =========================================================================
echo "Checking insurance assignment..."

INS_OID=$(clinical_query "SELECT OC_INSURANCE_OBJECTID FROM oc_insurances WHERE OC_INSURANCE_PATIENTUID='$PATIENT_ID' ORDER BY OC_INSURANCE_OBJECTID DESC LIMIT 1" 2>/dev/null | head -1 | tr -d '[:space:]')
INS_INSURARUID=$(clinical_query "SELECT OC_INSURANCE_INSURARUID FROM oc_insurances WHERE OC_INSURANCE_PATIENTUID='$PATIENT_ID' ORDER BY OC_INSURANCE_OBJECTID DESC LIMIT 1" 2>/dev/null | head -1 | tr -d '[:space:]')
INS_NR=$(clinical_query "SELECT OC_INSURANCE_NR FROM oc_insurances WHERE OC_INSURANCE_PATIENTUID='$PATIENT_ID' ORDER BY OC_INSURANCE_OBJECTID DESC LIMIT 1" 2>/dev/null | head -1)

INSURANCE_FOUND="false"
[ -n "$INS_OID" ] && INSURANCE_FOUND="true"

# Check if the assigned insurer matches the MediShield insurer
INSURANCE_MATCHES="false"
if [ -n "$INS_INSURARUID" ] && [ -n "$INSURAR_OID" ]; then
    # The INSURARUID may be in "serverid.objectid" format
    if [ "$INS_INSURARUID" = "$INSURAR_UID" ] || [ "$INS_INSURARUID" = "$INSURAR_OID" ]; then
        INSURANCE_MATCHES="true"
    fi
fi

echo "Insurance: found=$INSURANCE_FOUND insurar_uid=$INS_INSURARUID matches=$INSURANCE_MATCHES nr=$INS_NR"

# =========================================================================
# 3. Check service SPEC01
# =========================================================================
echo "Checking service SPEC01..."

SERVICE_OID=$(clinical_query "SELECT OC_PRESTATION_OBJECTID FROM oc_prestations WHERE OC_PRESTATION_CODE='SPEC01' LIMIT 1" 2>/dev/null | head -1 | tr -d '[:space:]')
SERVICE_PRICE=$(clinical_query "SELECT OC_PRESTATION_PRICE FROM oc_prestations WHERE OC_PRESTATION_CODE='SPEC01' LIMIT 1" 2>/dev/null | head -1 | tr -d '[:space:]')

SERVICE_FOUND="false"
[ -n "$SERVICE_OID" ] && SERVICE_FOUND="true"

echo "Service: found=$SERVICE_FOUND oid=$SERVICE_OID price=$SERVICE_PRICE"

# =========================================================================
# 4. Check charges for patient via encounters
#    Debets link to patients through: debet.ENCOUNTERUID -> encounter.PATIENTUID
# =========================================================================
echo "Checking charges..."

TOTAL_DEBETS=$(clinical_query "SELECT COUNT(*) FROM oc_debets d
    JOIN oc_encounters e ON d.OC_DEBET_ENCOUNTERUID = CONCAT(e.OC_ENCOUNTER_SERVERID, '.', e.OC_ENCOUNTER_OBJECTID)
    WHERE e.OC_ENCOUNTER_PATIENTUID='$PATIENT_ID'" 2>/dev/null | head -1 | tr -d '[:space:]')
[ -z "$TOTAL_DEBETS" ] && TOTAL_DEBETS="0"

# Count SPEC01-linked debets (the new charge)
SPEC01_CHARGE="0"
if [ -n "$SERVICE_OID" ]; then
    SPEC01_CHARGE=$(clinical_query "SELECT COUNT(*) FROM oc_debets d
        JOIN oc_encounters e ON d.OC_DEBET_ENCOUNTERUID = CONCAT(e.OC_ENCOUNTER_SERVERID, '.', e.OC_ENCOUNTER_OBJECTID)
        WHERE e.OC_ENCOUNTER_PATIENTUID='$PATIENT_ID'
        AND (d.OC_DEBET_PRESTATIONUID='$SERVICE_OID' OR d.OC_DEBET_PRESTATIONUID='1.$SERVICE_OID')" 2>/dev/null | head -1 | tr -d '[:space:]')
    [ -z "$SPEC01_CHARGE" ] && SPEC01_CHARGE="0"
fi

echo "Charges: total=$TOTAL_DEBETS spec01=$SPEC01_CHARGE"

# =========================================================================
# 5. Check insurer invoice (oc_insurarinvoices in openclinic_dbo)
# =========================================================================
echo "Checking insurer invoices..."

INV_OID=""
INV_FOUND="false"

if [ -n "$INSURAR_OID" ]; then
    INV_OID=$(clinical_query "SELECT OC_INSURARINVOICE_OBJECTID FROM oc_insurarinvoices
        WHERE OC_INSURARINVOICE_INSURARUID='$INSURAR_UID' OR OC_INSURARINVOICE_INSURARUID='$INSURAR_OID'
        ORDER BY OC_INSURARINVOICE_OBJECTID DESC LIMIT 1" 2>/dev/null | head -1 | tr -d '[:space:]')
    [ -n "$INV_OID" ] && INV_FOUND="true"
fi

echo "Insurer Invoice: found=$INV_FOUND oid=$INV_OID"

# =========================================================================
# 6. Trap check: GENCON charge must NOT be on any insurer invoice
# =========================================================================
echo "Checking trap..."

GENCON_OID=$(clinical_query "SELECT OC_PRESTATION_OBJECTID FROM oc_prestations WHERE OC_PRESTATION_CODE='GENCON' LIMIT 1" 2>/dev/null | head -1 | tr -d '[:space:]')
GENCON_ON_INV="0"
if [ -n "$GENCON_OID" ]; then
    GENCON_ON_INV=$(clinical_query "SELECT COUNT(*) FROM oc_debets d
        JOIN oc_encounters e ON d.OC_DEBET_ENCOUNTERUID = CONCAT(e.OC_ENCOUNTER_SERVERID, '.', e.OC_ENCOUNTER_OBJECTID)
        WHERE e.OC_ENCOUNTER_PATIENTUID='$PATIENT_ID'
        AND (d.OC_DEBET_PRESTATIONUID='$GENCON_OID' OR d.OC_DEBET_PRESTATIONUID='1.$GENCON_OID')
        AND d.OC_DEBET_INSURARINVOICEUID IS NOT NULL
        AND d.OC_DEBET_INSURARINVOICEUID != ''" 2>/dev/null | head -1 | tr -d '[:space:]')
    [ -z "$GENCON_ON_INV" ] && GENCON_ON_INV="0"
fi

echo "Trap: gencon_on_insurer_invoice=$GENCON_ON_INV"

# =========================================================================
# 7. App running check
# =========================================================================
APP_RUNNING="false"
pgrep -f firefox > /dev/null && APP_RUNNING="true"

# =========================================================================
# 8. Construct result JSON
# =========================================================================
TEMP_JSON=$(mktemp /tmp/result_icb.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "insurer": {
        "found": $INSURAR_FOUND,
        "oid": "$INSURAR_OID",
        "name": "$(echo "$INSURAR_NAME" | sed 's/"/\\"/g')",
        "language": "$INSURAR_LANG"
    },
    "insurance_assignment": {
        "found": $INSURANCE_FOUND,
        "insurar_uid": "$INS_INSURARUID",
        "matches_insurer": $INSURANCE_MATCHES,
        "policy_nr": "$(echo "$INS_NR" | sed 's/"/\\"/g')"
    },
    "service": {
        "found": $SERVICE_FOUND,
        "oid": "$SERVICE_OID",
        "price": "$SERVICE_PRICE"
    },
    "charges": {
        "total_for_patient": "$TOTAL_DEBETS",
        "spec01_linked": "$SPEC01_CHARGE"
    },
    "insurer_invoice": {
        "found": $INV_FOUND,
        "oid": "$INV_OID"
    },
    "trap": {
        "gencon_on_insurer_invoice": "$GENCON_ON_INV"
    },
    "app_running": $APP_RUNNING,
    "task_start_timestamp": $(cat /tmp/task_start_timestamp 2>/dev/null || echo "0"),
    "export_timestamp": $(date +%s)
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
