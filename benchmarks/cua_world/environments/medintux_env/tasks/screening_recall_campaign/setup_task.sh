#!/bin/bash
set -e
echo "=== Setting up Screening Recall Campaign task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create Documents directory
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 2

echo "Preparing database content..."

# Function to generate a UUID
gen_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# Function to insert patient
# insert_patient_sql "Nom" "Prenom" "Sex" "DOB" "Address" "CP" "Ville" "Tel"
insert_test_patient() {
    local guid=$(gen_uuid)
    local nom="$1"
    local prenom="$2"
    local sex="$3"
    local dob="$4"
    local addr="$5"
    local cp="$6"
    local ville="$7"
    local tel="$8"
    local titre="Mme"
    [ "$sex" == "M" ] && titre="M."
    
    # Random SSN-like number
    local numss="1$(date +%s%N | cut -c1-12)"

    # Insert into search index
    mysql -u root DrTuxTest -e \
        "INSERT IGNORE INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) VALUES ('$guid', '$nom', '$prenom', 'Dossier');" 2>/dev/null || true

    # Insert into demographics
    mysql -u root DrTuxTest -e \
        "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe, FchPat_Titre, FchPat_Adresse, FchPat_CP, FchPat_Ville, FchPat_Tel1, FchPat_NumSS) \
         VALUES ('$guid', '$nom', '$dob', '$sex', '$titre', '$addr', '$cp', '$ville', '$tel', '$numss');" 2>/dev/null || true
}

# Clear existing test data to ensure clean state (optional, but good for reproducibility)
# We won't delete everything, just specific test names if they exist to avoid duplicates
echo "Cleaning old test data..."
mysql -u root DrTuxTest -e "DELETE FROM fchpat WHERE FchPat_NomFille IN ('MARTIN','BERNARD','DUBOIS','THOMAS','ROBERT','PETIT','RICHARD','DURAND','MOREAU','LAURENT','SIMON','MICHEL','LEFEVRE','ROUX','DAVID','BERTRAND','MOREL','FOURNIER','GIRARD','BONNET');" 2>/dev/null || true
mysql -u root DrTuxTest -e "DELETE FROM IndexNomPrenom WHERE FchGnrl_NomDos IN ('MARTIN','BERNARD','DUBOIS','THOMAS','ROBERT','PETIT','RICHARD','DURAND','MOREAU','LAURENT','SIMON','MICHEL','LEFEVRE','ROUX','DAVID','BERTRAND','MOREL','FOURNIER','GIRARD','BONNET');" 2>/dev/null || true

echo "Inserting 20 supplemental patients..."

# --- ELIGIBLE (Females, 1950-1974) ---
# Complete contact info (7)
insert_test_patient "MARTIN" "Marie" "F" "1955-03-14" "12 Rue de la Paix" "75002" "Paris" "0145678901"
insert_test_patient "BERNARD" "Francoise" "F" "1960-07-22" "8 Avenue Victor Hugo" "69006" "Lyon" "0472345678"
insert_test_patient "DUBOIS" "Monique" "F" "1952-11-30" "45 Rue du Faubourg" "13001" "Marseille" "0491234567"
insert_test_patient "THOMAS" "Chantal" "F" "1968-02-18" "3 Place de la Liberte" "31000" "Toulouse" "0561789012"
insert_test_patient "ROBERT" "Sylvie" "F" "1971-09-05" "27 Boulevard Gambetta" "33000" "Bordeaux" "0556123456"
insert_test_patient "PETIT" "Catherine" "F" "1958-06-12" "15 Rue Jean Jaures" "44000" "Nantes" "0240567890"
insert_test_patient "RICHARD" "Dominique" "F" "1963-12-25" "6 Rue de Strasbourg" "67000" "Strasbourg" "0388456789"

# Edge case: Exactly 74 (born 1950)
insert_test_patient "MICHEL" "Annie" "F" "1950-05-15" "1 Place du Marche" "21000" "Dijon" "0380234567"

# Missing info (Eligible) (4)
# Missing Address
insert_test_patient "DURAND" "Nicole" "F" "1954-04-08" "" "" "" "0490123456"
# Missing Address + Phone
insert_test_patient "MOREAU" "Jacqueline" "F" "1966-08-17" "" "59000" "Lille" ""
# Missing CP + City + Phone
insert_test_patient "LAURENT" "Brigitte" "F" "1970-01-03" "9 Rue de la Gare" "" "" "0298765432"
# Missing Phone only
insert_test_patient "SIMON" "Isabelle" "F" "1957-10-20" "22 Rue Nationale" "37000" "Tours" ""

# --- INELIGIBLE (Age Control) ---
insert_test_patient "LEFEVRE" "Jeanne" "F" "1948-03-22" "5 Rue des Fleurs" "54000" "Nancy" "0383456789" # 76 yo
insert_test_patient "ROUX" "Amelie" "F" "1976-09-10" "14 Rue du Port" "29200" "Brest" "0298123456" # 48 yo
insert_test_patient "DAVID" "Emma" "F" "1980-04-18" "7 Avenue de la Mer" "06000" "Nice" "0493456789" # 44 yo

# --- INELIGIBLE (Gender Control) ---
insert_test_patient "BERTRAND" "Jean" "M" "1955-06-30" "10 Rue Voltaire" "75011" "Paris" "0143567890"
insert_test_patient "MOREL" "Pierre" "M" "1962-12-01" "33 Cours Mirabeau" "13100" "Aix-en-Provence" "0442345678"
insert_test_patient "FOURNIER" "Jacques" "M" "1958-08-25" "18 Rue de Rome" "13006" "Marseille" "0491567890"
insert_test_patient "GIRARD" "Philippe" "M" "1965-03-14" "21 Rue Pasteur" "38000" "Grenoble" "0476234567"
insert_test_patient "BONNET" "Andre" "M" "1970-11-09" "4 Place Bellecour" "69002" "Lyon" "0478901234"

# Ensure MedinTux Manager is running
launch_medintux_manager

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="