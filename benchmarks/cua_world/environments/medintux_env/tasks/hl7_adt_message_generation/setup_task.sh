#!/bin/bash
set -e
echo "=== Setting up HL7 ADT Message Generation Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
if ! pgrep -f "mysqld" > /dev/null; then
    echo "Starting MySQL..."
    service mysql start
    sleep 5
fi

# Clean up previous runs
rm -rf /home/ga/hl7_output
rm -f /tmp/hl7_task_result.json

# Insert required test patients if they don't exist
# We use the shared insert_patient function from task_utils.sh
# Usage: insert_patient "GUID" "NOM" "Prenom" "YYYY-MM-DD" "H|F" "Titre" "Adresse" "CP" "Ville" "Tel" "NumSS"

echo "Ensuring test patients exist..."

# 1. MOREAU Claire
if [ "$(patient_exists 'MOREAU' 'Claire')" -eq 0 ]; then
    GUID_MOREAU=$(uuidgen)
    insert_patient "$GUID_MOREAU" "MOREAU" "Claire" "1987-04-22" "F" "Mme" "15 Rue de la Paix" "75002" "Paris" "0145678901" "2870475002123 45"
    echo "Inserted MOREAU Claire"
fi

# 2. BERNARD Philippe
if [ "$(patient_exists 'BERNARD' 'Philippe')" -eq 0 ]; then
    GUID_BERNARD=$(uuidgen)
    insert_patient "$GUID_BERNARD" "BERNARD" "Philippe" "1955-11-03" "M" "M." "8 Avenue des Champs" "69003" "Lyon" "0478123456" "1551169003456 78"
    echo "Inserted BERNARD Philippe"
fi

# 3. PETIT Isabelle
if [ "$(patient_exists 'PETIT' 'Isabelle')" -eq 0 ]; then
    GUID_PETIT=$(uuidgen)
    insert_patient "$GUID_PETIT" "PETIT" "Isabelle" "2001-08-15" "F" "Mlle" "22 Boulevard Maritime" "13008" "Marseille" "0491234567" "2010813008789 01"
    echo "Inserted PETIT Isabelle"
fi

# Record initial patient count
PATIENT_COUNT=$(count_patients)
echo "$PATIENT_COUNT" > /tmp/initial_patient_count.txt
echo "Database ready with $PATIENT_COUNT patients."

# Take initial screenshot (likely of terminal or empty desktop)
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="