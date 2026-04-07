#!/bin/bash
set -e
echo "=== Setting up Lab Result Import Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt
date '+%Y-%m-%d %H:%M:%S' > /tmp/task_start_iso.txt

# Ensure MySQL is ready
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
# Wait for MySQL to be responsive
for i in {1..10}; do
    if mysqladmin ping -h localhost --silent; then
        break
    fi
    sleep 1
done

# Define the patients to ensure they exist
# Using arrays for: Name, Firstname, DOB, Sex, GUID
# GUIDs generated deterministically for this task to ensure clean cleanup
declare -A PATIENTS
PATIENTS["DUBOIS_Thomas"]="1980-05-12|M|TASK_LAB_001"
PATIENTS["LEROY_Sophie"]="1992-11-30|F|TASK_LAB_002"
PATIENTS["MOREAU_Lucas"]="1955-03-22|M|TASK_LAB_003"
PATIENTS["PETIT_Emma"]="2001-08-14|F|TASK_LAB_004"

echo "Preparing database with required patients..."

for key in "${!PATIENTS[@]}"; do
    NAME=$(echo "$key" | cut -d_ -f1)
    FIRST=$(echo "$key" | cut -d_ -f2)
    IFS='|' read -r DOB SEX GUID <<< "${PATIENTS[$key]}"
    
    # Check if exists
    COUNT=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_NomDos='$NAME' AND FchGnrl_Prenom='$FIRST'" 2>/dev/null || echo 0)
    
    if [ "$COUNT" -eq 0 ]; then
        echo "Creating patient: $NAME $FIRST"
        
        # Insert into Index
        mysql -u root DrTuxTest -e \
            "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) \
             VALUES ('$GUID', '$NAME', '$FIRST', 'Dossier')" 2>/dev/null
             
        # Insert into Details (fchpat)
        # Using placeholder address/SSN as they aren't critical for this task
        mysql -u root DrTuxTest -e \
            "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe, FchPat_Ville, FchPat_NumSS) \
             VALUES ('$GUID', '$NAME', '$DOB', '$SEX', 'Paris', '1000000000000')" 2>/dev/null
    else
        echo "Patient $NAME $FIRST already exists."
        # Get existing GUID to clean up notes
        EXISTING_GUID=$(mysql -u root DrTuxTest -N -e "SELECT FchGnrl_IDDos FROM IndexNomPrenom WHERE FchGnrl_NomDos='$NAME' AND FchGnrl_Prenom='$FIRST' LIMIT 1")
        GUID="$EXISTING_GUID"
    fi
    
    # CLEANUP: Delete any existing notes (Rubriques) created TODAY for this patient
    # This ensures the verifier doesn't pick up results from a previous run
    mysql -u root DrTuxTest -e \
        "DELETE FROM Rubriques WHERE Rub_IDDos='$GUID' AND Rub_Date >= CURDATE()" 2>/dev/null || true
done

# Create the input file
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/incoming_labs.txt << 'EOF'
LABORATORY RESULTS - URGENT
Date: 2024-10-24

1. Patient: DUBOIS, Thomas (DOB: 1980-05-12)
   Test: Potassium
   Value: 6.2 mmol/L
   Ref Range: 3.5 - 5.0
   (Status: HIGH)

2. Patient: LEROY, Sophie (DOB: 1992-11-30)
   Test: Ferritin
   Value: 45 ng/mL
   Ref Range: 15 - 150
   (Status: NORMAL)

3. Patient: MOREAU, Lucas (DOB: 1955-03-22)
   Test: Glucose (Fasting)
   Value: 0.95 g/L
   Ref Range: 0.70 - 1.10
   (Status: NORMAL)

4. Patient: PETIT, Emma (DOB: 2001-08-14)
   Test: Hemoglobin
   Value: 8.1 g/dL
   Ref Range: 12.0 - 16.0
   (Status: LOW)
EOF

chown ga:ga /home/ga/Documents/incoming_labs.txt

# Launch MedinTux
echo "Launching MedinTux..."
launch_medintux_manager

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="