#!/bin/bash
echo "=== Setting up add_prescription task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Kill any existing MedinTux instance
pkill -f "Manager.exe" 2>/dev/null || true
pkill -f "wine" 2>/dev/null || true
sleep 3

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 2

# Ensure patient BERNARD Pierre exists in the real MedinTux schema
# Real tables: IndexNomPrenom + fchpat (NOT Personnes)
BERNARD_COUNT=$(mysql -u root DrTuxTest -N -e \
    "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_NomDos='BERNARD' AND FchGnrl_Prenom='Pierre'" \
    2>/dev/null || echo 0)

if [ "$BERNARD_COUNT" -eq 0 ]; then
    echo "Inserting patient BERNARD Pierre..."
    GUID="$(cat /proc/sys/kernel/random/uuid | tr '[:lower:]' '[:upper:]')"
    mysql -u root DrTuxTest -e \
        "INSERT IGNORE INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) \
         VALUES ('$GUID', 'BERNARD', 'Pierre', 'Dossier')" 2>/dev/null || true
    mysql -u root DrTuxTest -e \
        "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe, FchPat_Titre, \
         FchPat_Adresse, FchPat_CP, FchPat_Ville, FchPat_Tel1, FchPat_NumSS) \
         VALUES ('$GUID', 'BERNARD', '1968-11-30', 'M', 'M.', '22 Chemin des Pins', 33000, 'Bordeaux', \
         '05.56.44.55.66', '1681133000088')" 2>/dev/null || true
fi

# Verify patient
echo "Patient BERNARD Pierre verified."
mysql -u root DrTuxTest -e \
    "SELECT i.FchGnrl_NomDos, i.FchGnrl_Prenom, f.FchPat_Nee, f.FchPat_Ville \
     FROM IndexNomPrenom i JOIN fchpat f ON i.FchGnrl_IDDos=f.FchPat_GUID_Doss \
     WHERE i.FchGnrl_NomDos='BERNARD' AND i.FchGnrl_Prenom='Pierre'" 2>/dev/null || true

# Launch MedinTux Manager (extracts Qt DLLs if needed, waits for window)
launch_medintux_manager

echo "=== add_prescription task setup complete ==="
echo "Task: Create prescription for BERNARD Pierre (Bisoprolol + Furosemide) in MedinTux"
