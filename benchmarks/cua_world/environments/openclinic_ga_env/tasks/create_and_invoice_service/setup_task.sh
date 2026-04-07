#!/bin/bash
echo "=== Setting up Create and Invoice Service task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
record_task_start /tmp/task_start_timestamp

# -----------------------------------------------------------------------------
# 1. Prepare Patient (Darwin Charles, ID 10004)
# -----------------------------------------------------------------------------
PATIENT_ID=10004
PATIENT_FIRST="Darwin"
PATIENT_LAST="Charles"

echo "Checking for patient $PATIENT_FIRST $PATIENT_LAST (ID: $PATIENT_ID)..."

# Check existence in admin view
EXISTS=$(admin_query "SELECT COUNT(*) FROM adminview WHERE personid=$PATIENT_ID" | tr -d '[:space:]')

if [ "$EXISTS" = "0" ] || [ -z "$EXISTS" ]; then
    echo "Patient not found. Re-seeding database..."
    /opt/openclinic/mysql5/bin/mysql -S /tmp/mysql5.sock -u root < /workspace/config/seed_data.sql 2>/dev/null || true
    # Double check
    EXISTS_NOW=$(admin_query "SELECT COUNT(*) FROM adminview WHERE personid=$PATIENT_ID" | tr -d '[:space:]')
    if [ "$EXISTS_NOW" = "0" ]; then
        echo "ERROR: Failed to seed patient $PATIENT_ID."
        exit 1
    fi
fi

# Ensure health record exists (required for encounters/charges)
HR_EXISTS=$(clinical_query "SELECT COUNT(*) FROM healthrecord WHERE personId=$PATIENT_ID" | tr -d '[:space:]')
if [ "$HR_EXISTS" = "0" ] || [ -z "$HR_EXISTS" ]; then
    echo "Creating health record for patient..."
    clinical_query "INSERT IGNORE INTO healthrecord (healthRecordId, personId, serverid, version, versionserverid, dateBegin) VALUES ($PATIENT_ID, $PATIENT_ID, 1, 1, 1, NOW())" 2>/dev/null || true
fi

# -----------------------------------------------------------------------------
# 2. Clean State: Remove Service TELE01 and associated data if exists
# -----------------------------------------------------------------------------
echo "Cleaning up previous task artifacts..."

# Get Service ID if it exists
SERVICE_UID=$(clinical_query "SELECT OC_PRESTATION_OBJECTID FROM oc_prestations WHERE OC_PRESTATION_CODE='TELE01'" | head -1 | tr -d '[:space:]')

if [ -n "$SERVICE_UID" ]; then
    echo "Found existing service TELE01 (ID: $SERVICE_UID). Cleaning up..."
    
    # Delete Invoices containing this service for this patient
    # (Complex delete, simplifying by removing recent invoices for this patient)
    clinical_query "DELETE FROM oc_patientinvoices WHERE OC_PATIENTINVOICE_PATIENTID=$PATIENT_ID AND OC_PATIENTINVOICE_DATE > DATE_SUB(NOW(), INTERVAL 1 DAY)" 2>/dev/null || true
    
    # Delete Debets/Charges for this service
    clinical_query "DELETE FROM oc_debets WHERE OC_DEBET_PRESTATIONUID='$SERVICE_UID'" 2>/dev/null || true
    
    # Delete the Service itself
    clinical_query "DELETE FROM oc_prestations WHERE OC_PRESTATION_OBJECTID='$SERVICE_UID'" 2>/dev/null || true
fi

# Also ensure no 'Telehealth Video Call' exists by name
clinical_query "DELETE FROM oc_prestations WHERE OC_PRESTATION_DESCRIPTION LIKE 'Telehealth Video Call%'" 2>/dev/null || true

# -----------------------------------------------------------------------------
# 3. Record Initial State
# -----------------------------------------------------------------------------
# Count invoices for patient
INITIAL_INVOICES=$(clinical_query "SELECT COUNT(*) FROM oc_patientinvoices WHERE OC_PATIENTINVOICE_PATIENTID=$PATIENT_ID" | tr -d '[:space:]' || echo "0")
echo "$INITIAL_INVOICES" > /tmp/initial_invoice_count

echo "Setup complete. Patient $PATIENT_ID ready. Service TELE01 cleaned."

# -----------------------------------------------------------------------------
# 4. Launch Application
# -----------------------------------------------------------------------------
ensure_openclinic_browser "http://localhost:10088/openclinic"
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png