#!/bin/bash
echo "=== Setting up Post-Op Follow-up Audit Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
wait_mysql_ready

# Create ground truth directory
mkdir -p /var/lib/medintux
chmod 755 /var/lib/medintux

# ==============================================================================
# DATA INJECTION
# We will inject 6 patients with specific scenarios to test the agent's logic.
# ==============================================================================
echo "Injecting clinical data..."

# Helper to generate GUID
gen_guid() {
    cat /proc/sys/kernel/random/uuid | tr '[:lower:]' '[:upper:]'
}

# Helper to insert patient
# insert_patient_data GUID NOM PRENOM DOB SEXE
insert_patient_data() {
    local guid=$1
    local nom=$2
    local prenom=$3
    local dob=$4
    local sexe=$5
    
    # Insert into search index
    mysql -u root DrTuxTest -e \
        "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) VALUES ('$guid', '$nom', '$prenom', 'Dossier');"
    
    # Insert into details
    mysql -u root DrTuxTest -e \
        "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe) VALUES ('$guid', '$nom', '$dob', '$sexe');"
}

# Helper to insert note
# insert_note GUID_NOTE GUID_PAT DATE TEXT TYPE
insert_note() {
    local guid_note=$1
    local guid_pat=$2
    local date_note=$3
    local text=$4
    local type=$5
    
    # Rubriques table structure assumption based on MedinTux: 
    # Rbq_PrimKey, Rbq_PrimKey_Pat, Rbq_Date, Rbq_NomRub, Rbq_Text
    # Note: Rbq_Text might be BLOB, passing string usually works in MySQL shell
    mysql -u root DrTuxTest -e \
        "INSERT INTO Rubriques (Rbq_PrimKey, Rbq_PrimKey_Pat, Rbq_Date, Rbq_NomRub, Rbq_Text) VALUES ('$guid_note', '$guid_pat', '$date_note 10:00:00', '$type', '$text');"
}

# ------------------------------------------------------------------------------
# SCENARIO 1: Compliant (Follow-up on Day 2)
# ------------------------------------------------------------------------------
GUID_1=$(gen_guid)
insert_patient_data "$GUID_1" "DUPONT" "Michel" "1950-01-15" "M"
insert_note "$(gen_guid)" "$GUID_1" "2024-01-15" "Chirurgie cataracte OD. Phaco + IOL. RAS." "Chirurgie"
insert_note "$(gen_guid)" "$GUID_1" "2024-01-17" "Consultation post-op J+2. Oeil calme." "Consultation"

# ------------------------------------------------------------------------------
# SCENARIO 2: Non-Compliant (No follow-up at all)
# ------------------------------------------------------------------------------
GUID_2=$(gen_guid)
insert_patient_data "$GUID_2" "DURAND" "Jean" "1948-03-22" "M"
insert_note "$(gen_guid)" "$GUID_2" "2024-02-10" "Opération de la cataracte OG. Déroulement normal." "Chirurgie"
# No follow-up note

# ------------------------------------------------------------------------------
# SCENARIO 3: Non-Compliant (Follow-up too late - Day 30)
# ------------------------------------------------------------------------------
GUID_3=$(gen_guid)
insert_patient_data "$GUID_3" "MARTIN" "Paul" "1955-07-30" "M"
insert_note "$(gen_guid)" "$GUID_3" "2024-03-05" "Chirurgie cataracte OD. Implant torique." "Chirurgie"
insert_note "$(gen_guid)" "$GUID_3" "2024-04-05" "Contrôle à 1 mois. Bonne récupération." "Consultation"

# ------------------------------------------------------------------------------
# SCENARIO 4: Compliant (Follow-up on Day 7 - Boundary condition)
# ------------------------------------------------------------------------------
GUID_4=$(gen_guid)
insert_patient_data "$GUID_4" "BERNARD" "Marie" "1960-11-12" "F"
insert_note "$(gen_guid)" "$GUID_4" "2024-04-20" "Opération de la cataracte OG." "Chirurgie"
insert_note "$(gen_guid)" "$GUID_4" "2024-04-27" "Visite de contrôle J+7. Cornée claire." "Consultation"

# ------------------------------------------------------------------------------
# SCENARIO 5: Compliant (Follow-up on Day 1 - Boundary condition)
# ------------------------------------------------------------------------------
GUID_5=$(gen_guid)
insert_patient_data "$GUID_5" "PETIT" "Claire" "1972-09-05" "F"
insert_note "$(gen_guid)" "$GUID_5" "2024-05-12" "Chirurgie cataracte OD." "Chirurgie"
insert_note "$(gen_guid)" "$GUID_5" "2024-05-13" "Contrôle J+1. RAS." "Consultation"

# ------------------------------------------------------------------------------
# SCENARIO 6: Non-Compliant (Follow-up on Day 8 - Boundary condition)
# ------------------------------------------------------------------------------
GUID_6=$(gen_guid)
insert_patient_data "$GUID_6" "LEROY" "Marc" "1965-02-28" "M"
insert_note "$(gen_guid)" "$GUID_6" "2024-06-01" "Opération de la cataracte OG." "Chirurgie"
insert_note "$(gen_guid)" "$GUID_6" "2024-06-09" "Patient vu pour contrôle (J+8). Retard de cicatrisation." "Consultation"


# Save Ground Truth to hidden file
cat > /var/lib/medintux/ground_truth_audit.json << EOF
{
    "non_compliant": [
        {"guid": "$GUID_2", "nom": "DURAND", "reason": "No follow-up"},
        {"guid": "$GUID_3", "nom": "MARTIN", "reason": "Late follow-up (Day 30)"},
        {"guid": "$GUID_6", "nom": "LEROY", "reason": "Late follow-up (Day 8)"}
    ],
    "compliant": [
        {"guid": "$GUID_1", "nom": "DUPONT", "reason": "Day 2"},
        {"guid": "$GUID_4", "nom": "BERNARD", "reason": "Day 7"},
        {"guid": "$GUID_5", "nom": "PETIT", "reason": "Day 1"}
    ]
}
EOF

# Ensure MedinTux Manager is running (provides context for agent)
launch_medintux_manager

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Data injected. Ground truth saved."