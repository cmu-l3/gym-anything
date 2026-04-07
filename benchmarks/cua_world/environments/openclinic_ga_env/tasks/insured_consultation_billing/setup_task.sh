#!/bin/bash
echo "=== Setting up Insured Consultation Billing task ==="

source /workspace/scripts/task_utils.sh

PATIENT_ID=10002
# High IDs to avoid conflicts with existing data
TRAP_ENCOUNTER_OID=88002
TRAP_DEBET_OID=88003
GENCON_OID=88001

# =========================================================================
# 1. Clean up previous task artifacts BEFORE recording timestamp
#    NOTE: All billing/insurer tables are in openclinic_dbo (not ocadmin_dbo).
#    Table names use "insurar" (not "insurer").
# =========================================================================
echo "Cleaning up previous task artifacts..."

# --- Remove any MediShield insurer and cascade ---
# Get insurer object IDs matching our target
INSURER_IDS=$(clinical_query "SELECT OC_INSURAR_OBJECTID FROM oc_insurars WHERE OC_INSURAR_NAME LIKE '%MediShield%'" 2>/dev/null)
for iid in $INSURER_IDS; do
    iid=$(echo "$iid" | tr -d '[:space:]')
    [ -z "$iid" ] && continue
    # UID format is "serverid.objectid"
    IUID="1.$iid"
    # Remove insurer invoices referencing this insurer
    clinical_query "DELETE FROM oc_insurarinvoices WHERE OC_INSURARINVOICE_INSURARUID='$IUID'" 2>/dev/null || true
    # Remove debets linked to insurance assignments for this insurer
    clinical_query "DELETE FROM oc_debets WHERE OC_DEBET_INSURANCEUID IN (SELECT CONCAT(OC_INSURANCE_SERVERID,'.',OC_INSURANCE_OBJECTID) FROM oc_insurances WHERE OC_INSURANCE_INSURARUID='$IUID')" 2>/dev/null || true
    # Remove insurance assignments for this insurer
    clinical_query "DELETE FROM oc_insurances WHERE OC_INSURANCE_INSURARUID='$IUID'" 2>/dev/null || true
done
# Remove the insurer records themselves
clinical_query "DELETE FROM oc_insurars WHERE OC_INSURAR_NAME LIKE '%MediShield%'" 2>/dev/null || true

# --- Remove ALL insurance assignments for patient 10002 ---
clinical_query "DELETE FROM oc_insurances WHERE OC_INSURANCE_PATIENTUID='$PATIENT_ID'" 2>/dev/null || true

# --- Remove service SPEC01 and debets referencing it ---
SPEC01_UID=$(clinical_query "SELECT OC_PRESTATION_OBJECTID FROM oc_prestations WHERE OC_PRESTATION_CODE='SPEC01'" 2>/dev/null | head -1 | tr -d '[:space:]')
if [ -n "$SPEC01_UID" ]; then
    clinical_query "DELETE FROM oc_debets WHERE OC_DEBET_PRESTATIONUID='$SPEC01_UID' OR OC_DEBET_PRESTATIONUID='1.$SPEC01_UID'" 2>/dev/null || true
    clinical_query "DELETE FROM oc_prestations WHERE OC_PRESTATION_OBJECTID='$SPEC01_UID'" 2>/dev/null || true
fi
clinical_query "DELETE FROM oc_prestations WHERE OC_PRESTATION_CODE='SPEC01'" 2>/dev/null || true

# --- Remove debets linked to encounters for patient 10002 that have insurer invoice refs ---
# (Preserve the trap debet which we will re-insert below)
clinical_query "DELETE d FROM oc_debets d
    JOIN oc_encounters e ON d.OC_DEBET_ENCOUNTERUID = CONCAT(e.OC_ENCOUNTER_SERVERID, '.', e.OC_ENCOUNTER_OBJECTID)
    WHERE e.OC_ENCOUNTER_PATIENTUID='$PATIENT_ID'
    AND d.OC_DEBET_INSURARINVOICEUID IS NOT NULL
    AND d.OC_DEBET_INSURARINVOICEUID != ''" 2>/dev/null || true

# --- Remove our specific trap encounter and debet (to re-create fresh) ---
clinical_query "DELETE FROM oc_debets WHERE OC_DEBET_OBJECTID=$TRAP_DEBET_OID" 2>/dev/null || true
clinical_query "DELETE FROM oc_encounters WHERE OC_ENCOUNTER_OBJECTID=$TRAP_ENCOUNTER_OID" 2>/dev/null || true

# --- Remove insurer invoices created during previous runs ---
clinical_query "DELETE FROM oc_insurarinvoices WHERE OC_INSURARINVOICE_OBJECTID > 80000" 2>/dev/null || true

# =========================================================================
# 2. Record task start timestamp (anti-gaming)
# =========================================================================
record_task_start /tmp/task_start_timestamp

# =========================================================================
# 3. Ensure patient 10002 (Carlos Mendoza) exists with health record
# =========================================================================
echo "Verifying patient $PATIENT_ID..."

EXISTS=$(admin_query "SELECT COUNT(*) FROM adminview WHERE personid=$PATIENT_ID" | tr -d '[:space:]')
if [ "$EXISTS" = "0" ] || [ -z "$EXISTS" ]; then
    echo "Patient not found. Re-seeding..."
    /opt/openclinic/mysql5/bin/mysql -S /tmp/mysql5.sock -u root < /workspace/config/seed_data.sql 2>/dev/null || true
fi

HR_EXISTS=$(clinical_query "SELECT COUNT(*) FROM healthrecord WHERE personId=$PATIENT_ID" | tr -d '[:space:]')
if [ "$HR_EXISTS" = "0" ] || [ -z "$HR_EXISTS" ]; then
    clinical_query "INSERT IGNORE INTO healthrecord (healthRecordId, personId, serverid, version, versionserverid, dateBegin) VALUES ($PATIENT_ID, $PATIENT_ID, 1, 1, 1, NOW())" 2>/dev/null || true
fi

# =========================================================================
# 4. Seed pre-existing uninsured charge (THE TRAP)
#    Chain: encounter -> debet -> prestation (GENCON)
# =========================================================================
echo "Seeding pre-existing uninsured charge..."

# Ensure GENCON service exists
/opt/openclinic/mysql5/bin/mysql -S /tmp/mysql5.sock -u root openclinic_dbo -e \
    "INSERT IGNORE INTO oc_prestations (OC_PRESTATION_OBJECTID, OC_PRESTATION_CODE, OC_PRESTATION_DESCRIPTION, OC_PRESTATION_PRICE, OC_PRESTATION_UPDATETIME, OC_PRESTATION_UPDATEUID, OC_PRESTATION_VERSION) VALUES ($GENCON_OID, 'GENCON', 'General Consultation', 30.00, NOW(), 1, 1)" 2>/dev/null || true

GENCON_UID=$(/opt/openclinic/mysql5/bin/mysql -S /tmp/mysql5.sock -u root openclinic_dbo -N -e "SELECT OC_PRESTATION_OBJECTID FROM oc_prestations WHERE OC_PRESTATION_CODE='GENCON' LIMIT 1" 2>/dev/null | head -1 | tr -d '[:space:]')
echo "GENCON prestation UID: $GENCON_UID"

# Create an encounter for the old consultation (14 days ago)
/opt/openclinic/mysql5/bin/mysql -S /tmp/mysql5.sock -u root openclinic_dbo -e \
    "INSERT INTO oc_encounters (OC_ENCOUNTER_SERVERID, OC_ENCOUNTER_OBJECTID, OC_ENCOUNTER_TYPE, OC_ENCOUNTER_BEGINDATE, OC_ENCOUNTER_PATIENTUID, OC_ENCOUNTER_CREATETIME, OC_ENCOUNTER_UPDATETIME, OC_ENCOUNTER_UPDATEUID, OC_ENCOUNTER_VERSION) VALUES (1, $TRAP_ENCOUNTER_OID, 'visit.consult', DATE_SUB(NOW(), INTERVAL 14 DAY), '$PATIENT_ID', NOW(), NOW(), '1', 1)" 2>&1 || echo "WARNING: Encounter insert failed (may already exist)"

# Create the pre-existing debet (no insurance, no insurer invoice)
# ENCOUNTERUID format is "serverid.objectid"
/opt/openclinic/mysql5/bin/mysql -S /tmp/mysql5.sock -u root openclinic_dbo -e \
    "INSERT INTO oc_debets (OC_DEBET_SERVERID, OC_DEBET_OBJECTID, OC_DEBET_DATE, OC_DEBET_AMOUNT, OC_DEBET_ENCOUNTERUID, OC_DEBET_PRESTATIONUID, OC_DEBET_QUANTITY, OC_DEBET_DESCRIPTION, OC_DEBET_CREATETIME, OC_DEBET_UPDATETIME, OC_DEBET_UPDATEUID, OC_DEBET_VERSION) VALUES (1, $TRAP_DEBET_OID, DATE_SUB(CURDATE(), INTERVAL 14 DAY), 30.00, '1.$TRAP_ENCOUNTER_OID', '$GENCON_UID', 1, 'General Consultation - prior uninsured visit', NOW(), NOW(), '1', 1)" 2>&1 || echo "WARNING: Debet insert failed (may already exist)"

echo "Pre-existing GENCON charge seeded (encounter=$TRAP_ENCOUNTER_OID, debet=$TRAP_DEBET_OID)."

# =========================================================================
# 5. Record initial state for anti-gaming
# =========================================================================
INITIAL_INSURAR_COUNT=$(clinical_query "SELECT COUNT(*) FROM oc_insurars" 2>/dev/null | tr -d '[:space:]' || echo "0")
echo "$INITIAL_INSURAR_COUNT" > /tmp/initial_insurar_count

# Count debets linked to patient 10002 via encounters
INITIAL_DEBET_COUNT=$(clinical_query "SELECT COUNT(*) FROM oc_debets d JOIN oc_encounters e ON d.OC_DEBET_ENCOUNTERUID = CONCAT(e.OC_ENCOUNTER_SERVERID,'.', e.OC_ENCOUNTER_OBJECTID) WHERE e.OC_ENCOUNTER_PATIENTUID='$PATIENT_ID'" 2>/dev/null | tr -d '[:space:]' || echo "0")
echo "$INITIAL_DEBET_COUNT" > /tmp/initial_debet_count

# =========================================================================
# 6. Launch application
# =========================================================================
ensure_openclinic_browser "http://localhost:10088/openclinic"
sleep 2

take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup complete ==="
echo "Patient $PATIENT_ID ready. Trap encounter+debet seeded."
