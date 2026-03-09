#!/bin/bash
echo "=== Setting up add_consultation task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Kill any existing MedinTux instance
pkill -f "Manager.exe" 2>/dev/null || true
pkill -f "wine" 2>/dev/null || true
sleep 3

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 2

# Ensure patient DUBOIS Marie-Claire exists in the real MedinTux schema
# Real tables: IndexNomPrenom + fchpat (NOT Personnes)
DUBOIS_COUNT=$(mysql -u root DrTuxTest -N -e \
    "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_NomDos='DUBOIS' AND FchGnrl_Prenom='Marie-Claire'" \
    2>/dev/null || echo 0)

if [ "$DUBOIS_COUNT" -eq 0 ]; then
    echo "Inserting patient DUBOIS Marie-Claire..."
    GUID="$(cat /proc/sys/kernel/random/uuid | tr '[:lower:]' '[:upper:]')"
    mysql -u root DrTuxTest -e \
        "INSERT IGNORE INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) \
         VALUES ('$GUID', 'DUBOIS', 'Marie-Claire', 'Dossier')" 2>/dev/null || true
    mysql -u root DrTuxTest -e \
        "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe, FchPat_Titre, \
         FchPat_Adresse, FchPat_CP, FchPat_Ville, FchPat_Tel1, FchPat_NumSS) \
         VALUES ('$GUID', 'DUBOIS', '1962-07-08', 'F', 'Mme', '7 Impasse du Moulin', 13001, 'Marseille', \
         '04.91.55.66.77', '2620613001045')" 2>/dev/null || true
fi

# Look up patient GUID for reference
DUBOIS_GUID=$(mysql -u root DrTuxTest -N -e \
    "SELECT FchGnrl_IDDos FROM IndexNomPrenom WHERE FchGnrl_NomDos='DUBOIS' AND FchGnrl_Prenom='Marie-Claire' LIMIT 1" \
    2>/dev/null || echo "")
echo "DUBOIS Marie-Claire GUID: $DUBOIS_GUID"

# Show patient info for context
echo "Patient details:"
mysql -u root DrTuxTest -e \
    "SELECT i.FchGnrl_NomDos, i.FchGnrl_Prenom, f.FchPat_Nee, f.FchPat_Ville \
     FROM IndexNomPrenom i JOIN fchpat f ON i.FchGnrl_IDDos=f.FchPat_GUID_Doss \
     WHERE i.FchGnrl_NomDos='DUBOIS' AND i.FchGnrl_Prenom='Marie-Claire'" 2>/dev/null || true

# Launch MedinTux Manager (extracts Qt DLLs if needed, waits for window)
launch_medintux_manager

echo "=== add_consultation task setup complete ==="
echo "Task: Record consultation for DUBOIS Marie-Claire in MedinTux"
