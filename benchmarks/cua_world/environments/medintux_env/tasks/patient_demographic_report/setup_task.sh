#!/bin/bash
set -e
echo "=== Setting up Patient Demographics Report Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Remove any previous report
rm -f /home/ga/patient_demographics_report.txt

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 2

# ==============================================================================
# DATA PREPARATION
# Insert 8 specific patients into MedinTux database (DrTuxTest)
# ==============================================================================
echo "Preparing patient database..."

# Clear existing test data to ensure exact counts
mysql -u root DrTuxTest -e "DELETE FROM fchpat; DELETE FROM IndexNomPrenom;" 2>/dev/null || true

# Function to insert a patient safely
add_patient_db() {
    local nom="$1"
    local prenom="$2"
    local dob="$3"
    local sexe="$4"
    local ville="$5"
    
    # Generate a random UUID for the GUID
    local guid=$(cat /proc/sys/kernel/random/uuid | tr '[:lower:]' '[:upper:]')
    
    # Insert into search index
    mysql -u root DrTuxTest -e \
        "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) \
         VALUES ('$guid', '$nom', '$prenom', 'Dossier');"
         
    # Insert into patient details
    # Note: FchPat_Sexe expects 'M' or 'F' usually, but MedinTux GUI might show H/F. 
    # In DB: M=Male, F=Female. 
    # For this dataset: H (Homme) -> M in DB
    local db_sex="$sexe"
    if [ "$sexe" == "H" ]; then db_sex="M"; fi
    
    mysql -u root DrTuxTest -e \
        "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe, FchPat_Ville) \
         VALUES ('$guid', '$nom', '$dob', '$db_sex', '$ville');"
}

# Insert the 8 patients
# 1. MARTIN Sophie, 1965-03-12, F, Toulouse
add_patient_db "MARTIN" "Sophie" "1965-03-12" "F" "Toulouse"

# 2. BERNARD Pierre, 1978-11-25, H, Toulouse
add_patient_db "BERNARD" "Pierre" "1978-11-25" "H" "Toulouse"

# 3. DUBOIS Marie, 1990-06-08, F, Montpellier
add_patient_db "DUBOIS" "Marie" "1990-06-08" "F" "Montpellier"

# 4. THOMAS Jean, 1952-09-17, H, Toulouse
add_patient_db "THOMAS" "Jean" "1952-09-17" "H" "Toulouse"

# 5. ROBERT Claire, 2001-02-28, F, Bordeaux
add_patient_db "ROBERT" "Claire" "2001-02-28" "F" "Bordeaux"

# 6. PETIT François, 1985-07-03, H, Toulouse
add_patient_db "PETIT" "François" "1985-07-03" "H" "Toulouse"

# 7. RICHARD Isabelle, 1970-12-19, F, Montpellier
add_patient_db "RICHARD" "Isabelle" "1970-12-19" "F" "Montpellier"

# 8. DURAND Michel, 1948-04-22, H, Bordeaux
add_patient_db "DURAND" "Michel" "1948-04-22" "H" "Bordeaux"

echo "Database populated with 8 patients."

# ==============================================================================
# LAUNCH APPLICATION
# ==============================================================================
# Launch MedinTux Manager
launch_medintux_manager

# Ensure window is maximized
sleep 5
DISPLAY=:1 wmctrl -r "Manager" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="