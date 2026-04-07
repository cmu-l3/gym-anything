#!/bin/bash
# Setup script for Annual Diabetic Care Review task in OSCAR EMR
# Patient: Fatima Al-Hassan (DOB: 1978-08-09) — Patient 7 in seed_patients.sql

echo "=== Setting up Annual Diabetic Review Task ==="

source /workspace/scripts/task_utils.sh

# ── Verify patient exists ──────────────────────────────
PATIENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='Fatima' AND last_name='Al-Hassan'" || echo "0")
if [ "${PATIENT_COUNT:-0}" -eq 0 ]; then
    echo "ERROR: Patient Fatima Al-Hassan not found in database"
    exit 1
fi
echo "Patient Fatima Al-Hassan confirmed."

PATIENT_NO=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Fatima' AND last_name='Al-Hassan' LIMIT 1")
echo "Patient demographic_no: $PATIENT_NO"
echo "$PATIENT_NO" > /tmp/task_patient_no_diabetic_review

# ── Ensure patient is admitted to OSCAR program (required for encounter access) ──
# Without this, accessing the patient's encounter/chart gives "Access Denied"
oscar_query "DELETE FROM admission WHERE client_id='$PATIENT_NO'" 2>/dev/null || true
oscar_query "SET sql_mode=''; INSERT INTO admission (client_id, admission_status, program_id, provider_no, admission_date, admission_from_transfer, discharge_from_transfer, lastUpdateDate) VALUES ('$PATIENT_NO', 'current', 1, '999998', NOW(), 0, 0, NOW());" 2>/dev/null || true
ADMISSION_COUNT=$(oscar_query "SELECT COUNT(*) FROM admission WHERE client_id='$PATIENT_NO' AND admission_status='current'" || echo "0")
echo "Admission record: $ADMISSION_COUNT (expect 1)"

# ── Clean slate: remove stale data BEFORE recording baseline ──
oscar_query "DELETE FROM measurements WHERE demographicNo='$PATIENT_NO'" 2>/dev/null || true
echo "Cleared measurements."

oscar_query "DELETE FROM drugs WHERE demographic_no='$PATIENT_NO'" 2>/dev/null || true
echo "Cleared drugs."

oscar_query "DELETE FROM allergies WHERE demographic_no='$PATIENT_NO'" 2>/dev/null || true
echo "Cleared allergies."

oscar_query "DELETE FROM casemgmt_note WHERE demographic_no='$PATIENT_NO'" 2>/dev/null || true
echo "Cleared encounter notes."

oscar_query "DELETE FROM tickler WHERE demographic_no='$PATIENT_NO'" 2>/dev/null || true
echo "Cleared ticklers."

# ── Seed chronic disease medication regimen ────────────
# These represent Fatima's CURRENT medications before today's visit.
# Realistic Type 2 Diabetes + Hypertension + Dyslipidemia profile.

# Metformin 500mg BID — Type 2 Diabetes (stays active)
oscar_query "INSERT INTO drugs
    (demographic_no, provider_no, rx_date, end_date, GN, BN, dosage, route,
     freqcode, duration, durunit, quantity, \`repeat\`, archived,
     lastUpdateDate, position, dispenseInternal)
VALUES ('$PATIENT_NO', '999998', DATE_SUB(CURDATE(), INTERVAL 180 DAY),
        '0001-01-01', 'Metformin', 'Glucophage', '500mg', 'PO', 'bid',
        '90', 'd', '180', 3, 0, NOW(), 0, 0);" 2>/dev/null || true
echo "Seeded Metformin 500mg BID."

# Glyburide 5mg OD — Type 2 Diabetes (AGENT MUST DISCONTINUE THIS)
oscar_query "INSERT INTO drugs
    (demographic_no, provider_no, rx_date, end_date, GN, BN, dosage, route,
     freqcode, duration, durunit, quantity, \`repeat\`, archived,
     lastUpdateDate, position, dispenseInternal)
VALUES ('$PATIENT_NO', '999998', DATE_SUB(CURDATE(), INTERVAL 180 DAY),
        '0001-01-01', 'Glyburide', 'Diabeta', '5mg', 'PO', 'od',
        '90', 'd', '90', 3, 0, NOW(), 0, 0);" 2>/dev/null || true
echo "Seeded Glyburide 5mg OD (target for discontinuation)."

# Ramipril 10mg OD — Hypertension (stays active)
oscar_query "INSERT INTO drugs
    (demographic_no, provider_no, rx_date, end_date, GN, BN, dosage, route,
     freqcode, duration, durunit, quantity, \`repeat\`, archived,
     lastUpdateDate, position, dispenseInternal)
VALUES ('$PATIENT_NO', '999998', DATE_SUB(CURDATE(), INTERVAL 180 DAY),
        '0001-01-01', 'Ramipril', 'Altace', '10mg', 'PO', 'od',
        '90', 'd', '90', 3, 0, NOW(), 0, 0);" 2>/dev/null || true
echo "Seeded Ramipril 10mg OD."

# Atorvastatin 20mg OD — Dyslipidemia (stays active)
oscar_query "INSERT INTO drugs
    (demographic_no, provider_no, rx_date, end_date, GN, BN, dosage, route,
     freqcode, duration, durunit, quantity, \`repeat\`, archived,
     lastUpdateDate, position, dispenseInternal)
VALUES ('$PATIENT_NO', '999998', DATE_SUB(CURDATE(), INTERVAL 180 DAY),
        '0001-01-01', 'Atorvastatin', 'Lipitor', '20mg', 'PO', 'od',
        '90', 'd', '90', 3, 0, NOW(), 0, 0);" 2>/dev/null || true
echo "Seeded Atorvastatin 20mg OD."

# ── Seed pre-existing allergy (NOT sulfonamides) ──────
# Note: 'position' column is NOT NULL with no default — must be specified
oscar_query "INSERT INTO allergies
    (demographic_no, entry_date, DESCRIPTION, reaction,
     severity_of_reaction, TYPECODE, archived, lastUpdateDate, position)
VALUES ('$PATIENT_NO', CURDATE(), 'Penicillin', 'Anaphylaxis',
        '3', 0, 0, NOW(), 0);" 2>/dev/null || true
echo "Seeded Penicillin allergy (Anaphylaxis, Severe)."

# ── Record baseline counts AFTER seeding ───────────────
INITIAL_DRUG_COUNT=$(oscar_query "SELECT COUNT(*) FROM drugs WHERE demographic_no='$PATIENT_NO' AND archived=0" || echo "0")
echo "$INITIAL_DRUG_COUNT" > /tmp/initial_drug_count_dr

INITIAL_ALLERGY_COUNT=$(oscar_query "SELECT COUNT(*) FROM allergies WHERE demographic_no='$PATIENT_NO' AND archived=0" || echo "0")
echo "$INITIAL_ALLERGY_COUNT" > /tmp/initial_allergy_count_dr

INITIAL_MEASUREMENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM measurements WHERE demographicNo='$PATIENT_NO'" || echo "0")
echo "$INITIAL_MEASUREMENT_COUNT" > /tmp/initial_measurement_count_dr

INITIAL_NOTE_COUNT=$(oscar_query "SELECT COUNT(*) FROM casemgmt_note WHERE demographic_no='$PATIENT_NO'" || echo "0")
echo "$INITIAL_NOTE_COUNT" > /tmp/initial_note_count_dr

INITIAL_TICKLER_COUNT=$(oscar_query "SELECT COUNT(*) FROM tickler WHERE demographic_no='$PATIENT_NO'" || echo "0")
echo "$INITIAL_TICKLER_COUNT" > /tmp/initial_tickler_count_dr

# ── Record task start timestamp ────────────────────────
date +%s > /tmp/task_start_timestamp

# ── Verify seeding ────────────────────────────────────
echo ""
echo "Baseline counts:"
echo "  Active drugs:    $INITIAL_DRUG_COUNT (expect 4)"
echo "  Allergies:       $INITIAL_ALLERGY_COUNT (expect 1)"
echo "  Measurements:    $INITIAL_MEASUREMENT_COUNT (expect 0)"
echo "  Encounter notes: $INITIAL_NOTE_COUNT (expect 0)"
echo "  Ticklers:        $INITIAL_TICKLER_COUNT (expect 0)"

[ "$INITIAL_DRUG_COUNT" -ne 4 ] && echo "WARNING: Expected 4 drugs, got $INITIAL_DRUG_COUNT"
[ "$INITIAL_ALLERGY_COUNT" -ne 1 ] && echo "WARNING: Expected 1 allergy, got $INITIAL_ALLERGY_COUNT"

# ── Launch browser on OSCAR login page ─────────────────
ensure_firefox_on_oscar

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Annual Diabetic Review Task Setup Complete ==="
echo "Patient: Fatima Al-Hassan (DOB: August 9, 1978)"
echo "Current medications: Metformin 500mg, Glyburide 5mg, Ramipril 10mg, Atorvastatin 20mg"
echo "Current allergies: Penicillin (Anaphylaxis)"
echo ""
