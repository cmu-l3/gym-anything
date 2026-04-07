#!/bin/bash
echo "=== Setting up Legacy Record Family Extraction Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 2

# ==============================================================================
# DATA PREPARATION
# ==============================================================================

# 1. CLEANUP: Remove the children if they already exist (from previous runs)
echo "Cleaning up any existing records for Paul and Juliette LEGRAND..."
delete_patient "LEGRAND" "Paul"
delete_patient "LEGRAND" "Juliette"

# 2. CLEANUP: Remove mother to ensure clean slate, then recreate
delete_patient "LEGRAND" "Catherine"

# 3. CREATE MOTHER RECORD with the specific Note
echo "Creating source record for Catherine LEGRAND..."
GUID_MOTHER="GUID-LEGRAND-CATH-001"
NOTE_CONTENT="ATTENTION: Dossier papier archivé. Enfants non informatisés: -- Paul (Garçon), né le 14 février 2015. -- Juliette (Fille), née le 30 juin 2018. Créer leurs dossiers à cette adresse."

# Insert into Index (Search)
mysql -u root DrTuxTest -e \
    "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) \
     VALUES ('$GUID_MOTHER', 'LEGRAND', 'Catherine', 'Dossier')" 2>/dev/null

# Insert into Details (fchpat) with the Note
# Note: FchPat_Note is the field for notes/remarques
mysql -u root DrTuxTest -e \
    "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe, FchPat_Titre, \
     FchPat_Adresse, FchPat_CP, FchPat_Ville, FchPat_Tel1, FchPat_NumSS, FchPat_Note) \
     VALUES ('$GUID_MOTHER', 'LEGRAND', '1982-05-10', 'F', 'Mme', \
     '10 Rue de la Paix', 75001, 'Paris', '01.42.61.88.99', '2820575001001', '$NOTE_CONTENT')" 2>/dev/null

# ==============================================================================
# RECORD INITIAL STATE
# ==============================================================================
# Count patients to detect changes later
count_patients > /tmp/initial_patient_count.txt

# ==============================================================================
# APP LAUNCH
# ==============================================================================
# Kill any existing instances
pkill -f "Manager.exe" 2>/dev/null || true
pkill -f "wine" 2>/dev/null || true
sleep 2

# Launch MedinTux Manager
echo "Launching MedinTux Manager..."
launch_medintux_manager

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Mother record created with hidden family data in notes."