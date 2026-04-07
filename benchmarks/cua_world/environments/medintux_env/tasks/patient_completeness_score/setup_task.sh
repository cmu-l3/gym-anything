#!/bin/bash
echo "=== Setting up patient_completeness_score task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 3

# ==============================================================================
# DATA PREPARATION
# We need to insert patients with specific missing fields to test the scoring logic.
# ==============================================================================

echo "Preparing test data in DrTuxTest..."

# 1. Clean up specific test patients if they exist to avoid duplicates
# We'll use a prefix or specific GUIDs to track them, but for this task 
# we'll just delete based on the names we are about to insert.
mysql -u root DrTuxTest -e "DELETE FROM fchpat WHERE FchPat_NomFille LIKE 'TEST_%';" 2>/dev/null || true
mysql -u root DrTuxTest -e "DELETE FROM IndexNomPrenom WHERE FchGnrl_NomDos LIKE 'TEST_%';" 2>/dev/null || true

# Function to insert a patient with specific fields
# Usage: insert_test_patient "GUID" "NOM" "PRENOM" "FIELDS_SQL_VALUES"
insert_test_patient() {
    local guid="$1"
    local nom="$2"
    local prenom="$3"
    local fields_values="$4" # e.g., "'1980-01-01', 'M', ..." matching the schema columns order after GUID/Nom

    # Insert into Index (Search)
    mysql -u root DrTuxTest -e \
        "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) \
         VALUES ('$guid', '$nom', '$prenom', 'Dossier')" 2>/dev/null

    # Insert into Details
    # Columns: GUID, Nom, Nee, Sexe, Titre, Adresse, CP, Ville, Tel1, NumSS
    mysql -u root DrTuxTest -e \
        "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe, FchPat_Titre, FchPat_Adresse, FchPat_CP, FchPat_Ville, FchPat_Tel1, FchPat_NumSS) \
         VALUES ('$guid', '$nom', $fields_values)" 2>/dev/null
}

# --- Patient 1: 100% Complete (9/9) ---
GUID1="TEST-GUID-001"
# Values: Nee, Sexe, Titre, Adresse, CP, Ville, Tel1, NumSS
insert_test_patient "$GUID1" "TEST_COMPLETE" "Alice" \
    "'1980-05-15', 'F', 'Mme', '10 Rue Complete', '75001', 'Paris', '0102030405', '2800575001001'"

# --- Patient 2: Missing Phone and SSN (7/9) -> 77.8% ---
GUID2="TEST-GUID-002"
insert_test_patient "$GUID2" "TEST_MOSTLY" "Bob" \
    "'1990-12-01', 'M', 'M.', '20 Ave Mostly', '69002', 'Lyon', '', ''"

# --- Patient 3: Missing Address, CP, Ville, Phone, SSN (4/9) -> 44.4% ---
GUID3="TEST-GUID-003"
insert_test_patient "$GUID3" "TEST_PARTIAL" "Charlie" \
    "'1975-03-20', 'M', 'M.', '', '', '', '', ''"

# --- Patient 4: Missing almost everything except Name, Sex (2/9) -> 22.2% ---
# Note: Nom is always present as it's part of the insert logic
GUID4="TEST-GUID-004"
insert_test_patient "$GUID4" "TEST_EMPTY" "Danielle" \
    "NULL, 'F', '', '', '', '', '', ''"

# --- Patient 5: Another Complete one for sorting check ---
GUID5="TEST-GUID-005"
insert_test_patient "$GUID5" "TEST_ZETA" "Zoe" \
    "'1985-01-01', 'F', 'Mme', '1 Rue Zeta', '33000', 'Bordeaux', '0600000000', '2850133000000'"

echo "Test data inserted."

# Launch MedinTux Manager so the environment looks "live"
# (Even though the task is SQL based, the agent might check the UI)
launch_medintux_manager

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="