#!/bin/bash
# Export script for Medication Reconciliation Task

echo "=== Exporting Medication Reconciliation Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Target patient
PATIENT_PID=25

# Get initial counts
INITIAL_RX_COUNT=$(cat /tmp/initial_rx_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Get current prescription count for patient
CURRENT_RX_COUNT=$(openemr_query "SELECT COUNT(*) FROM prescriptions WHERE patient_id=$PATIENT_PID" 2>/dev/null || echo "0")

echo "Prescription count: initial=$INITIAL_RX_COUNT, current=$CURRENT_RX_COUNT"

# Query for all prescriptions for this patient
echo ""
echo "=== Querying prescriptions for patient PID=$PATIENT_PID ==="
ALL_RX=$(openemr_query "SELECT id, drug, dosage, quantity, form, route, date_added, active FROM prescriptions WHERE patient_id=$PATIENT_PID ORDER BY id DESC LIMIT 20" 2>/dev/null)
echo "All prescriptions for patient:"
echo "$ALL_RX"

# Check for each target medication
echo ""
echo "=== Checking for target medications ==="

# Lisinopril (ACE inhibitor)
LISINOPRIL=$(openemr_query "SELECT id, drug, dosage, date_added FROM prescriptions WHERE patient_id=$PATIENT_PID AND drug LIKE '%isinopril%' ORDER BY id DESC LIMIT 1" 2>/dev/null)
LISINOPRIL_FOUND="false"
LISINOPRIL_DRUG=""
LISINOPRIL_DOSE=""
if [ -n "$LISINOPRIL" ]; then
    LISINOPRIL_FOUND="true"
    LISINOPRIL_DRUG=$(echo "$LISINOPRIL" | cut -f2)
    LISINOPRIL_DOSE=$(echo "$LISINOPRIL" | cut -f3)
    echo "Lisinopril found: $LISINOPRIL"
fi

# Metformin (Biguanide)
METFORMIN=$(openemr_query "SELECT id, drug, dosage, date_added FROM prescriptions WHERE patient_id=$PATIENT_PID AND drug LIKE '%etformin%' ORDER BY id DESC LIMIT 1" 2>/dev/null)
METFORMIN_FOUND="false"
METFORMIN_DRUG=""
METFORMIN_DOSE=""
if [ -n "$METFORMIN" ]; then
    METFORMIN_FOUND="true"
    METFORMIN_DRUG=$(echo "$METFORMIN" | cut -f2)
    METFORMIN_DOSE=$(echo "$METFORMIN" | cut -f3)
    echo "Metformin found: $METFORMIN"
fi

# Atorvastatin (Statin)
ATORVASTATIN=$(openemr_query "SELECT id, drug, dosage, date_added FROM prescriptions WHERE patient_id=$PATIENT_PID AND drug LIKE '%torvastatin%' ORDER BY id DESC LIMIT 1" 2>/dev/null)
ATORVASTATIN_FOUND="false"
ATORVASTATIN_DRUG=""
ATORVASTATIN_DOSE=""
if [ -n "$ATORVASTATIN" ]; then
    ATORVASTATIN_FOUND="true"
    ATORVASTATIN_DRUG=$(echo "$ATORVASTATIN" | cut -f2)
    ATORVASTATIN_DOSE=$(echo "$ATORVASTATIN" | cut -f3)
    echo "Atorvastatin found: $ATORVASTATIN"
fi

# Aspirin (Antiplatelet)
ASPIRIN=$(openemr_query "SELECT id, drug, dosage, date_added FROM prescriptions WHERE patient_id=$PATIENT_PID AND drug LIKE '%spirin%' ORDER BY id DESC LIMIT 1" 2>/dev/null)
ASPIRIN_FOUND="false"
ASPIRIN_DRUG=""
ASPIRIN_DOSE=""
if [ -n "$ASPIRIN" ]; then
    ASPIRIN_FOUND="true"
    ASPIRIN_DRUG=$(echo "$ASPIRIN" | cut -f2)
    ASPIRIN_DOSE=$(echo "$ASPIRIN" | cut -f3)
    echo "Aspirin found: $ASPIRIN"
fi

# Omeprazole (PPI)
OMEPRAZOLE=$(openemr_query "SELECT id, drug, dosage, date_added FROM prescriptions WHERE patient_id=$PATIENT_PID AND drug LIKE '%meprazole%' ORDER BY id DESC LIMIT 1" 2>/dev/null)
OMEPRAZOLE_FOUND="false"
OMEPRAZOLE_DRUG=""
OMEPRAZOLE_DOSE=""
if [ -n "$OMEPRAZOLE" ]; then
    OMEPRAZOLE_FOUND="true"
    OMEPRAZOLE_DRUG=$(echo "$OMEPRAZOLE" | cut -f2)
    OMEPRAZOLE_DOSE=$(echo "$OMEPRAZOLE" | cut -f3)
    echo "Omeprazole found: $OMEPRAZOLE"
fi

# Count how many target medications were found
MEDS_FOUND=0
[ "$LISINOPRIL_FOUND" = "true" ] && MEDS_FOUND=$((MEDS_FOUND + 1))
[ "$METFORMIN_FOUND" = "true" ] && MEDS_FOUND=$((MEDS_FOUND + 1))
[ "$ATORVASTATIN_FOUND" = "true" ] && MEDS_FOUND=$((MEDS_FOUND + 1))
[ "$ASPIRIN_FOUND" = "true" ] && MEDS_FOUND=$((MEDS_FOUND + 1))
[ "$OMEPRAZOLE_FOUND" = "true" ] && MEDS_FOUND=$((MEDS_FOUND + 1))

echo ""
echo "Target medications found: $MEDS_FOUND / 5"

# Count new prescriptions added
NEW_RX_COUNT=$((CURRENT_RX_COUNT - INITIAL_RX_COUNT))
echo "New prescriptions added: $NEW_RX_COUNT"

# Escape special characters for JSON
escape_json() {
    echo "$1" | sed 's/"/\\"/g' | tr '\n' ' '
}

LISINOPRIL_DRUG_ESC=$(escape_json "$LISINOPRIL_DRUG")
LISINOPRIL_DOSE_ESC=$(escape_json "$LISINOPRIL_DOSE")
METFORMIN_DRUG_ESC=$(escape_json "$METFORMIN_DRUG")
METFORMIN_DOSE_ESC=$(escape_json "$METFORMIN_DOSE")
ATORVASTATIN_DRUG_ESC=$(escape_json "$ATORVASTATIN_DRUG")
ATORVASTATIN_DOSE_ESC=$(escape_json "$ATORVASTATIN_DOSE")
ASPIRIN_DRUG_ESC=$(escape_json "$ASPIRIN_DRUG")
ASPIRIN_DOSE_ESC=$(escape_json "$ASPIRIN_DOSE")
OMEPRAZOLE_DRUG_ESC=$(escape_json "$OMEPRAZOLE_DRUG")
OMEPRAZOLE_DOSE_ESC=$(escape_json "$OMEPRAZOLE_DOSE")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/med_recon_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "initial_rx_count": ${INITIAL_RX_COUNT:-0},
    "current_rx_count": ${CURRENT_RX_COUNT:-0},
    "new_rx_count": ${NEW_RX_COUNT:-0},
    "target_medications_found": $MEDS_FOUND,
    "medications": {
        "lisinopril": {
            "found": $LISINOPRIL_FOUND,
            "drug": "$LISINOPRIL_DRUG_ESC",
            "dose": "$LISINOPRIL_DOSE_ESC"
        },
        "metformin": {
            "found": $METFORMIN_FOUND,
            "drug": "$METFORMIN_DRUG_ESC",
            "dose": "$METFORMIN_DOSE_ESC"
        },
        "atorvastatin": {
            "found": $ATORVASTATIN_FOUND,
            "drug": "$ATORVASTATIN_DRUG_ESC",
            "dose": "$ATORVASTATIN_DOSE_ESC"
        },
        "aspirin": {
            "found": $ASPIRIN_FOUND,
            "drug": "$ASPIRIN_DRUG_ESC",
            "dose": "$ASPIRIN_DOSE_ESC"
        },
        "omeprazole": {
            "found": $OMEPRAZOLE_FOUND,
            "drug": "$OMEPRAZOLE_DRUG_ESC",
            "dose": "$OMEPRAZOLE_DOSE_ESC"
        }
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/medication_reconciliation_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/medication_reconciliation_result.json
chmod 666 /tmp/medication_reconciliation_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/medication_reconciliation_result.json"
cat /tmp/medication_reconciliation_result.json

echo ""
echo "=== Export Complete ==="
