#!/bin/bash
set -e
echo "=== Setting up merge_duplicate_patients task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 2

# Define GUIDs for the duplicates
GUID_A="DUP-MERGE-AAA-001"
GUID_B="DUP-MERGE-BBB-002"

echo "Cleaning up any existing DUPONT test records..."
mysql -u root DrTuxTest -e "DELETE FROM fchpat WHERE FchPat_GUID_Doss IN ('$GUID_A', '$GUID_B') OR (FchPat_NomFille='DUPONT' AND FchPat_Nee='1967-04-12')" 2>/dev/null || true
mysql -u root DrTuxTest -e "DELETE FROM IndexNomPrenom WHERE FchGnrl_IDDos IN ('$GUID_A', '$GUID_B') OR (FchGnrl_NomDos='DUPONT' AND FchGnrl_Prenom LIKE 'Marie%')" 2>/dev/null || true

echo "Inserting Duplicate Record A (Phone, no Address, Name no hyphen)..."
# Record A: DUPONT Marie Claire, Phone yes, Address no
mysql -u root DrTuxTest -e \
    "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) \
     VALUES ('$GUID_A', 'DUPONT', 'Marie Claire', 'Dossier')"

mysql -u root DrTuxTest -e \
    "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe, FchPat_Titre, \
     FchPat_Adresse, FchPat_CP, FchPat_Ville, FchPat_Tel1, FchPat_NumSS) \
     VALUES ('$GUID_A', 'DUPONT', '1967-04-12', 'F', 'Mme', \
     '', '0', '', '0145678901', '2670475002123')"

echo "Inserting Duplicate Record B (Address, no Phone, Name hyphen)..."
# Record B: DUPONT Marie-Claire, Phone no, Address yes
mysql -u root DrTuxTest -e \
    "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) \
     VALUES ('$GUID_B', 'DUPONT', 'Marie-Claire', 'Dossier')"

mysql -u root DrTuxTest -e \
    "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe, FchPat_Titre, \
     FchPat_Adresse, FchPat_CP, FchPat_Ville, FchPat_Tel1, FchPat_NumSS) \
     VALUES ('$GUID_B', 'DUPONT', '1967-04-12', 'F', 'Mme', \
     '15 Rue de la Paix', '75002', 'Paris', '', '2670475002123')"

# Record initial state for verification
INITIAL_COUNT=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_NomDos='DUPONT' AND FchGnrl_Prenom LIKE 'Marie%'" 2>/dev/null)
echo "$INITIAL_COUNT" > /tmp/initial_count.txt

echo "Initial DUPONT records: $INITIAL_COUNT"

# Launch MedinTux Manager
# This ensures the window is open for the agent to use GUI if they wish
launch_medintux_manager

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="