#!/bin/bash
set -e
echo "=== Setting up Backfill Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Kill any running MedinTux instances to ensure clean start
pkill -f "Manager.exe" 2>/dev/null || true
pkill -f "wine" 2>/dev/null || true
sleep 3

# 2. Ensure MySQL is running
if ! pgrep mysqld > /dev/null; then
    echo "Starting MySQL..."
    systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
    sleep 5
fi

# 3. Create the source data file
cat > /home/ga/Documents/lucas_growth_data.txt << EOF
HISTORICAL GROWTH DATA - PATIENT: Lucas GRANDJEAN (DOB: 15/06/2014)
Please enter these as individual historical observations in MedinTux.

Date: 2015-06-15 (Age 1)
Weight: 10.2 kg
Height: 76 cm

Date: 2016-06-15 (Age 2)
Weight: 12.5 kg
Height: 87 cm

Date: 2018-06-15 (Age 4)
Weight: 16.3 kg
Height: 103 cm

Date: 2020-06-15 (Age 6)
Weight: 20.5 kg
Height: 115 cm
EOF

chmod 644 /home/ga/Documents/lucas_growth_data.txt
chown ga:ga /home/ga/Documents/lucas_growth_data.txt

# 4. Prepare Patient Data
# Check if patient exists, if not create him. If yes, clear his notes.
echo "Preparing patient record..."
PATIENT_GUID=$(get_patient_guid "GRANDJEAN" "Lucas")

if [ -z "$PATIENT_GUID" ]; then
    echo "Creating patient Lucas GRANDJEAN..."
    # Generate a GUID
    NEW_GUID="GUID-$(date +%s)-${RANDOM}"
    # Insert: GUID, Nom, Prenom, DOB, Sex, Title, Address, CP, City, Phone, SSN
    insert_patient "$NEW_GUID" "GRANDJEAN" "Lucas" "2014-06-15" "M" "Enfant" "10 Rue des Lilas" "31000" "Toulouse" "0601020304" "1140631000001"
    echo "Patient created with GUID: $NEW_GUID"
else
    echo "Patient exists (GUID: $PATIENT_GUID). Clearing old notes..."
    # Clear any existing notes (Rubriques) for this patient to ensure clean verification
    # Note: MedinTux links Rubriques via GUID usually, but sometimes via Nom/Prenom in older versions.
    # We delete by both to be safe.
    mysql -u root DrTuxTest -e "DELETE FROM Rubriques WHERE Rub_GUID_Doss='$PATIENT_GUID'" 2>/dev/null || true
    mysql -u root DrTuxTest -e "DELETE FROM Rubriques WHERE Rub_NomDos='GRANDJEAN' AND Rub_Prenom='Lucas'" 2>/dev/null || true
fi

# 5. Launch MedinTux
echo "Launching MedinTux..."
launch_medintux_manager

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="