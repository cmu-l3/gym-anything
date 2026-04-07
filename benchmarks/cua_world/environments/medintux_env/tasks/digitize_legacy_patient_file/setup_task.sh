#!/bin/bash
echo "=== Setting up digitize_legacy_patient_file task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Create the source data file on the Desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/patient_intake_form.txt << 'EOF'
NEW PATIENT INTAKE FORM
-----------------------
Surname: CONNOR
First Name: Sarah
Date of Birth: 12/05/1965  (DD/MM/YYYY)
Sex: Female
Address: 1984 Cyberdyne Ave, 75012 Paris

MEDICAL HISTORY:
- Appendicectomy (1998)
- Fracture Tibia Right (2010)

ALLERGIES:
- Latex
- Penicillin
EOF
chown ga:ga /home/ga/Desktop/patient_intake_form.txt
chmod 644 /home/ga/Desktop/patient_intake_form.txt

# 3. Clean up any previous existence of this patient to ensure a clean start
# We need to delete from fchpat (details) and IndexNomPrenom (search index)
# and any associated documents in RubriquesHead/RubriquesBlobs
echo "Cleaning up previous test data..."

# Get GUID if exists
EXISTING_GUID=$(mysql -u root DrTuxTest -N -e \
    "SELECT FchGnrl_IDDos FROM IndexNomPrenom WHERE FchGnrl_NomDos='CONNOR' AND FchGnrl_Prenom='Sarah'" \
    2>/dev/null || echo "")

if [ -n "$EXISTING_GUID" ]; then
    echo "Found existing patient GUID: $EXISTING_GUID - Deleting..."
    
    # Delete documents
    mysql -u root DrTuxTest -e "DELETE FROM RubriquesBlobs WHERE RbDate_IDDos='$EXISTING_GUID'" 2>/dev/null || true
    mysql -u root DrTuxTest -e "DELETE FROM RubriquesHead WHERE RbDate_IDDos='$EXISTING_GUID'" 2>/dev/null || true
    
    # Delete patient details
    mysql -u root DrTuxTest -e "DELETE FROM fchpat WHERE FchPat_GUID_Doss='$EXISTING_GUID'" 2>/dev/null || true
    
    # Delete index
    mysql -u root DrTuxTest -e "DELETE FROM IndexNomPrenom WHERE FchGnrl_IDDos='$EXISTING_GUID'" 2>/dev/null || true
fi

# 4. Launch MedinTux Manager
echo "Launching MedinTux..."
launch_medintux_manager

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="