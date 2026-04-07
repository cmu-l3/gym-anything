#!/bin/bash
set -e
echo "=== Setting up FHIR Patient Export Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Clean up previous results
rm -f /home/ga/Documents/fhir_patients_bundle.json
rm -f /tmp/task_result.json

# Ensure MySQL is running
if ! pgrep mysqld > /dev/null; then
    echo "Starting MySQL..."
    service mysql start
    sleep 5
fi

# ============================================================
# Populate Database with Test Data
# ============================================================
echo "Injecting test patients into DrTuxTest..."

# Helper function to insert patient if not exists
# Args: IDDos(GUID), Nom, Prenom, Nee, Sexe(H/F), Ville, CP, NIR
insert_test_patient() {
    local guid="$1"
    local nom="$2"
    local prenom="$3"
    local nee="$4"
    local sexe="$5"
    local ville="$6"
    local cp="$7"
    local nir="$8"
    
    # Check if exists to avoid duplicates
    local count=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_NomDos='$nom' AND FchGnrl_Prenom='$prenom'" 2>/dev/null || echo 0)
    
    if [ "$count" -eq 0 ]; then
        echo "  Inserting $nom $prenom..."
        # Insert into IndexNomPrenom
        mysql -u root DrTuxTest -e \
            "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) VALUES ('$guid', '$nom', '$prenom', 'Dossier')"
            
        # Insert into fchpat
        # Note: Using random values for non-critical fields like Address/Tel to vary slightly, but critical fields fixed
        mysql -u root DrTuxTest -e \
            "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe, FchPat_Titre, FchPat_Adresse, FchPat_CP, FchPat_Ville, FchPat_Tel1, FchPat_NumSS) \
             VALUES ('$guid', '$nom', '$nee', '$sexe', 'M.', '10 Rue de la République', '$cp', '$ville', '0102030405', '$nir')"
    else
        echo "  Patient $nom $prenom already exists."
    fi
}

# Insert the 8 required test patients
# Using consistent GUIDs based on name hash or fixed strings would be better, but random is fine if we query by name
insert_test_patient "GUID_MARTIN_P" "MARTIN" "Pierre" "1952-03-14" "H" "Lyon" "69000" "152036912345678"
insert_test_patient "GUID_DUBOIS_M" "DUBOIS" "Marie" "1968-11-22" "F" "Marseille" "13000" "268111345678945"
insert_test_patient "GUID_LEROY_J" "LEROY" "Jacques" "1945-07-03" "H" "Paris" "75000" "145077523456712"
insert_test_patient "GUID_MOREAU_S" "MOREAU" "Sophie" "1983-05-19" "F" "Toulouse" "31000" "283053198765433"
insert_test_patient "GUID_LAURENT_A" "LAURENT" "Antoine" "1971-09-30" "H" "Bordeaux" "33000" "171093334567890"
insert_test_patient "GUID_BERNARD_C" "BERNARD" "Claire" "1990-01-08" "F" "Nantes" "44000" "290014456789067"
insert_test_patient "GUID_PETIT_F" "PETIT" "François" "1958-12-25" "H" "Strasbourg" "67000" "158126767890123"
insert_test_patient "GUID_ROUX_I" "ROUX" "Isabelle" "1976-06-17" "F" "Nice" "06000" "276060678901256"

# Record total patient count for verification comparison
TOTAL_PATIENTS=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_Type='Dossier'" 2>/dev/null || echo 0)
echo "$TOTAL_PATIENTS" > /tmp/initial_patient_count.txt
echo "Total patients in DB: $TOTAL_PATIENTS"

# ============================================================
# Application Launch
# ============================================================
# Launch MedinTux Manager so agent can explore if needed
echo "Launching MedinTux Manager..."
launch_medintux_manager

# Ensure correct window focus
WID=$(DISPLAY=:1 wmctrl -l | grep -i "manager" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="