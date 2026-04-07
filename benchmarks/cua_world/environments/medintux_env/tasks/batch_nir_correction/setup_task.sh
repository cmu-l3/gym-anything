#!/bin/bash
set -e
echo "=== Setting up batch_nir_correction task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
echo "Waiting for MySQL..."
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent; then break; fi
    sleep 1
done

# Prepare Data Arrays
# Format: Nom|Prenom|Nee|Sexe|OldSSN|NewSSN|InDB|InCSV
DATA_ROWS=(
    "MARTIN|Thomas|1980-05-12|M|TEMP|1 80 05 75 001 123 45|YES|YES"
    "DURAND|Sophie|1992-09-23|F|TEMP|2 92 09 33 001 456 89|YES|YES"
    "PETIT|Julie|1975-03-15|F|TEMP|2 75 03 69 123 789 12|YES|YES"
    "LEGRAND|Marc|1960-11-30|M|1 60 11 99 001 001 99|1 60 11 99 001 001 99|YES|NO"
    "ROBERT|Luc|1985-07-07|M|TEMP|1 85 07 44 001 002 33|NO|YES"
    "MOREL|Claire|1988-01-01|F|TEMP|2 88 01 75 001 999 01|YES|YES"
)

# Prepare CSV File
CSV_FILE="/home/ga/Documents/cpam_corrections.csv"
mkdir -p /home/ga/Documents
echo "Nom,Prenom,DateNaissance,NouveauNIR" > "$CSV_FILE"

echo "Resetting/Inserting test patients..."

for row in "${DATA_ROWS[@]}"; do
    IFS='|' read -r nom prenom nee sexe old_ssn new_ssn in_db in_csv <<< "$row"
    
    # Generate a deterministic GUID
    GUID=$(echo "${nom}${prenom}" | md5sum | cut -c1-32)
    
    # Clean up existing records to ensure fresh state
    delete_patient "$nom" "$prenom"
    
    # Determine DB SSN
    if [ "$old_ssn" == "TEMP" ]; then
        DB_SSN="0 00 00 00 000 000 00"
    else
        DB_SSN="$old_ssn"
    fi
    
    # Insert into DB if required
    if [ "$in_db" == "YES" ]; then
        insert_patient "$GUID" "$nom" "$prenom" "$nee" "$sexe" "M." "1 Rue Test" "75000" "Paris" "0102030405" "$DB_SSN"
    fi
    
    # Add to CSV if required (removing spaces from SSN for realism to test normalization)
    if [ "$in_csv" == "YES" ]; then
        CLEAN_SSN=$(echo "$new_ssn" | tr -d ' ')
        echo "${nom},${prenom},${nee},${CLEAN_SSN}" >> "$CSV_FILE"
    fi
done

# Fix permissions
chown ga:ga "$CSV_FILE"
rm -f /home/ga/Documents/missing_patients_log.txt 2>/dev/null || true

# Launch MedinTux Manager so the environment feels "alive" (optional for this DB task, but good for context)
# We won't wait aggressively for it since the task is primarily DB/Shell based
launch_medintux_manager > /dev/null 2>&1 &

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "CSV created at: $CSV_FILE"