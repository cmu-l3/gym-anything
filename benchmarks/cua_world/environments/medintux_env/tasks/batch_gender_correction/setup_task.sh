#!/bin/bash
set -e
echo "=== Setting up Task: Batch Gender Correction ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Start MySQL
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 3

# 2. Prepare Reference Data (Female Names List)
# Note: "Marie" is here, but "Jean-Marie" is not.
cat > /home/ga/female_first_names.txt << EOF
Isabelle
Martine
Catherine
Nathalie
Sandrine
Aurélie
Chantal
Monique
Marie
Julie
Sophie
EOF
chown ga:ga /home/ga/female_first_names.txt

# 3. Seed Database with Test Cases
echo "Seeding database with mixed gender accuracy..."

# Helper function for insertion
# Usage: insert_pat GUID LASTNAME FIRSTNAME DOB SEX
insert_pat() {
    local guid=$1
    local nom=$2
    local prenom=$3
    local dob=$4
    local sex=$5
    
    # Clean up any existing record with this GUID
    mysql -u root DrTuxTest -e "DELETE FROM fchpat WHERE FchPat_GUID_Doss='$guid'" 2>/dev/null || true
    mysql -u root DrTuxTest -e "DELETE FROM IndexNomPrenom WHERE FchGnrl_IDDos='$guid'" 2>/dev/null || true

    # Insert into search index
    mysql -u root DrTuxTest -e \
        "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) VALUES ('$guid', '$nom', '$prenom', 'Dossier')" 2>/dev/null
    
    # Insert into details (using 999 SSN to track test data)
    mysql -u root DrTuxTest -e \
        "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe, FchPat_NumSS) VALUES ('$guid', '$nom', '$dob', '$sex', '9990000000000')" 2>/dev/null
}

# GROUP A: TARGETS (Females misclassified as 'H') - MUST BE CHANGED TO 'F'
insert_pat "GUID_T1" "TEST_DURAND" "Isabelle" "1980-05-12" "H"
insert_pat "GUID_T2" "TEST_MARTIN" "Martine"  "1975-11-23" "H"
insert_pat "GUID_T3" "TEST_PETIT"  "Catherine" "1990-01-30" "H"
insert_pat "GUID_T4" "TEST_LEFEVRE" "Marie"    "1985-07-14" "H" # Strict check against Jean-Marie

# GROUP B: DISTRACTORS (Compound/Ambiguous males) - MUST REMAIN 'H'
insert_pat "GUID_D1" "TEST_BERNARD" "Jean-Marie" "1960-02-20" "H" # Contains 'Marie' but is male
insert_pat "GUID_D2" "TEST_MOREAU"  "Jean-Pierre" "1965-08-05" "H"
insert_pat "GUID_D3" "TEST_ROUX"    "Claude"      "1955-12-12" "H" # Ambiguous, not in list

# GROUP C: BASELINE (Correctly classified) - MUST REMAIN AS IS
insert_pat "GUID_B1" "TEST_DUPONT"  "Pierre" "1982-03-15" "H"
insert_pat "GUID_B2" "TEST_LEROY"   "Julie"  "1995-06-20" "F"

echo "Database seeded."

# 4. Launch MedinTux Manager (so agent can inspect if they want)
launch_medintux_manager

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="