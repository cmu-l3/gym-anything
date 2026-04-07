#!/bin/bash
set -e
echo "=== Setting up NIR Validation Audit Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
echo "Starting MySQL..."
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 3

# Helper to clear previous test data
clear_test_patient() {
    local nom="$1"
    mysql -u root DrTuxTest -e "DELETE FROM fchpat WHERE FchPat_NomFille='$nom';" 2>/dev/null || true
    mysql -u root DrTuxTest -e "DELETE FROM IndexNomPrenom WHERE FchGnrl_NomDos='$nom';" 2>/dev/null || true
}

echo "Cleaning up any previous test data..."
for name in AUBERT BEAUMONT CHEVALIER DUFOUR FABRE GARNIER HUBERT JOUBERT; do
    clear_test_patient "$name"
done

# Insert Test Patients
# Note: FchPat_NumSS is the NIR field
echo "Inserting test patients..."

# 1. VALID: AUBERT Marie (Key 39 is correct for 1850375012005)
insert_patient "NIRAV01" "AUBERT" "Marie" "1985-03-15" "F" "Mme" "10 Rue Valid" "75001" "Paris" "0102030405" "185037501200539"

# 2. VALID: BEAUMONT Claire (Key 13 is correct for 2900613001042)
insert_patient "NIRAV02" "BEAUMONT" "Claire" "1990-06-13" "F" "Mme" "20 Rue Valid" "13001" "Marseille" "0102030406" "290061300104213"

# 3. VALID: CHEVALIER Luc (Key 84 is correct for 1761169002118)
insert_patient "NIRAV03" "CHEVALIER" "Luc" "1976-11-20" "M" "M." "30 Rue Valid" "69002" "Lyon" "0102030407" "176116900211884"

# 4. INVALID_FORMAT: DUFOUR Henri (Too short)
insert_patient "NIRIF01" "DUFOUR" "Henri" "1972-08-22" "M" "M." "40 Rue BadFormat" "33000" "Bordeaux" "0102030408" "12345"

# 5. INVALID_FORMAT: FABRE Sylvie (Non-numeric)
insert_patient "NIRIF02" "FABRE" "Sylvie" "1980-01-01" "F" "Mme" "50 Rue BadFormat" "31000" "Toulouse" "0102030409" "ABC12345678901X"

# 6. INVALID_KEY: GARNIER Paul (Key 40 is WRONG for 1850375012005 - should be 39)
insert_patient "NIRIK01" "GARNIER" "Paul" "1985-03-15" "M" "M." "60 Rue BadKey" "44000" "Nantes" "0102030410" "185037501200540"

# 7. INVALID_KEY: HUBERT Anne (Key 14 is WRONG for 2900613001042 - should be 13)
insert_patient "NIRIK02" "HUBERT" "Anne" "1990-06-13" "F" "Mme" "70 Rue BadKey" "59000" "Lille" "0102030411" "290061300104214"

# 8. MISSING: JOUBERT Elise (Empty string)
insert_patient "NIRMS01" "JOUBERT" "Elise" "1988-04-30" "F" "Mme" "80 Rue Missing" "67000" "Strasbourg" "0102030412" ""

# Record initial patient count for verification
TOTAL_COUNT=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM fchpat" 2>/dev/null)
echo "$TOTAL_COUNT" > /tmp/initial_patient_count.txt
echo "Initial patient count: $TOTAL_COUNT"

# Launch MedinTux Manager to ensure environment looks correct
launch_medintux_manager

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="