#!/bin/bash
echo "=== Setting up create_clinical_stored_procedures task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 3

# Wait for MySQL
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        break
    fi
    sleep 1
done

# Ensure database exists and has data
# We rely on the standard MedinTux demo data installed in the environment
# But we must clean up any previous attempts at this task
echo "Cleaning up existing routines..."
mysql -u root DrTuxTest <<EOF
DROP FUNCTION IF EXISTS fn_patient_age;
DROP PROCEDURE IF EXISTS sp_search_patients;
DROP PROCEDURE IF EXISTS sp_age_pyramid;
DROP PROCEDURE IF EXISTS sp_practice_summary;
EOF

# Ensure there is at least one patient with a birthdate for testing
# Check for a specific test patient, insert if missing
TEST_GUID="TEST-PATIENT-GUID-001"
EXISTS=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM fchpat WHERE FchPat_GUID_Doss='$TEST_GUID'" 2>/dev/null || echo 0)

if [ "$EXISTS" -eq 0 ]; then
    echo "Inserting test patient for verification consistency..."
    # Insert into search index
    mysql -u root DrTuxTest -e \
        "INSERT IGNORE INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) VALUES ('$TEST_GUID', 'TESTER', 'John', 'Dossier')" 2>/dev/null || true
    
    # Insert patient details (Born 2000-01-01, so age is predictable)
    mysql -u root DrTuxTest -e \
        "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe, FchPat_Titre, FchPat_Adresse, FchPat_CP, FchPat_Ville, FchPat_Tel1, FchPat_NumSS) \
         VALUES ('$TEST_GUID', 'TESTER', '2000-01-01', 'M', 'M.', '123 Test St', 75000, 'Paris', '0102030405', '1000175000001')" 2>/dev/null || true
fi

# Launch MedinTux Manager (provides visual context for the schema)
launch_medintux_manager

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "MySQL Database 'DrTuxTest' is ready."
echo "Tables: IndexNomPrenom, fchpat"