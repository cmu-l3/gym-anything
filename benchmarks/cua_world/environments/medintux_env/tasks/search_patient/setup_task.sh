#!/bin/bash
echo "=== Setting up search_patient task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Kill any existing MedinTux instance
pkill -f "Manager.exe" 2>/dev/null || true
pkill -f "wine" 2>/dev/null || true
sleep 3

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 2

# Ensure patient SIMON Valérie exists in the real MedinTux schema
# Real tables: IndexNomPrenom (search index) + fchpat (patient details)
SIMON_COUNT=$(mysql -u root DrTuxTest -N -e \
    "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_NomDos='SIMON' AND FchGnrl_Prenom='Valérie'" \
    2>/dev/null || echo 0)

if [ "$SIMON_COUNT" -eq 0 ]; then
    echo "Inserting patient SIMON Valérie..."
    GUID="$(cat /proc/sys/kernel/random/uuid | tr '[:lower:]' '[:upper:]')"
    mysql -u root DrTuxTest -e \
        "INSERT IGNORE INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) \
         VALUES ('$GUID', 'SIMON', 'Valérie', 'Dossier')" 2>/dev/null || true
    mysql -u root DrTuxTest -e \
        "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe, FchPat_Titre, \
         FchPat_Adresse, FchPat_CP, FchPat_Ville, FchPat_Tel1, FchPat_NumSS) \
         VALUES ('$GUID', 'SIMON', '1970-10-19', 'F', 'Mme', '11 Rue de la Paix', 6000, 'Nice', \
         '04.93.22.33.44', '2701006000011')" 2>/dev/null || true
fi

# Verify patient data
echo "Patient SIMON Valérie data:"
mysql -u root DrTuxTest -e \
    "SELECT i.FchGnrl_NomDos, i.FchGnrl_Prenom, f.FchPat_Nee, f.FchPat_Ville, f.FchPat_Tel1 \
     FROM IndexNomPrenom i JOIN fchpat f ON i.FchGnrl_IDDos=f.FchPat_GUID_Doss \
     WHERE i.FchGnrl_NomDos='SIMON' AND i.FchGnrl_Prenom='Valérie'" 2>/dev/null || true

# Show total patient count
echo "Total patients in database:"
mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_Type='Dossier'" 2>/dev/null || true

# Launch MedinTux Manager (extracts Qt DLLs if needed, waits for window)
launch_medintux_manager

echo "=== search_patient task setup complete ==="
echo "Task: Search for SIMON Valérie and open her patient file in MedinTux"
