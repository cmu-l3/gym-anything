#!/bin/bash
echo "=== Setting up update_patient_info task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh
wait_for_postgres

# 1. Verify Ana Betz patient exists in the demo DB
ANA_EXISTS=$(gnuhealth_db_query "SELECT COUNT(*) FROM gnuhealth_patient gp JOIN party_party pp ON gp.party = pp.id WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'" | tr -d '[:space:]')
echo "Ana Betz patient found: $ANA_EXISTS"
if [ "${ANA_EXISTS:-0}" -eq 0 ]; then
    echo "WARNING: Ana Betz not found in demo database. Demo DB may not have been restored."
fi

# 2. Get Ana Betz's party ID and reset contact info for a clean start
ANA_PARTY_ID=$(gnuhealth_db_query "SELECT pp.id FROM party_party pp JOIN gnuhealth_patient gp ON gp.party = pp.id WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%' LIMIT 1" | tr -d '[:space:]')
if [ -n "$ANA_PARTY_ID" ]; then
    echo "Ana Betz party id: $ANA_PARTY_ID"
    # Remove existing mobile/email contact mechanisms to ensure clean start
    gnuhealth_db_query "DELETE FROM party_contact_mechanism WHERE party = $ANA_PARTY_ID AND type IN ('mobile', 'email')" 2>/dev/null || true
    echo "Cleared existing mobile/email contacts for clean test start"
fi

# 3. Also clear occupation/education from party_party (that's where the patient form Demographics reads from)
#    and also clear SES assessment records for a clean start
ANA_PATIENT_ID=$(gnuhealth_db_query "SELECT gp.id FROM gnuhealth_patient gp JOIN party_party pp ON gp.party = pp.id WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%' LIMIT 1" | tr -d '[:space:]')
if [ -n "$ANA_PARTY_ID" ]; then
    # Clear occupation and education directly on party_party (where the Demographics section reads from)
    gnuhealth_db_query "UPDATE party_party SET occupation = NULL, education = NULL WHERE id = $ANA_PARTY_ID" 2>/dev/null || true
    echo "Cleared party_party occupation/education for clean test start (party_id=$ANA_PARTY_ID)"
fi
if [ -n "$ANA_PATIENT_ID" ]; then
    # Also clear any SES assessment records (created via the SES Assessment sub-form)
    gnuhealth_db_query "DELETE FROM gnuhealth_ses_assessment WHERE patient = $ANA_PATIENT_ID" 2>/dev/null || true
    echo "Cleared SES assessments for clean test start (patient_id=$ANA_PATIENT_ID)"
fi

# 4. Record initial state
rm -f /tmp/ana_betz_initial.txt 2>/dev/null || true
echo "Ana Betz party_id=$ANA_PARTY_ID patient_id=$ANA_PATIENT_ID; contacts, party occupation/education, and SES cleared" > /tmp/ana_betz_initial.txt
chmod 666 /tmp/ana_betz_initial.txt 2>/dev/null || true

# 5. Ensure GNU Health server is running
if ! curl -s --max-time 5 http://localhost:8000/ > /dev/null 2>&1; then
    echo "Starting GNU Health server..."
    systemctl start gnuhealth
    sleep 15
fi

# 6. Ensure logged in and navigate to Patients list
ensure_gnuhealth_logged_in "http://localhost:8000/"
sleep 5

# 7. Take initial screenshot
take_screenshot /tmp/update_patient_info_initial.png

echo "=== update_patient_info task setup complete ==="
echo "Task: Update contact info for Ana Isabel Betz (GNU777ORG)"
echo "Navigate to Patients, open Ana Betz's record, update mobile, email, occupation, education"
