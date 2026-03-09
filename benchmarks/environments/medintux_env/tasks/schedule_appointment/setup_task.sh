#!/bin/bash
echo "=== Setting up schedule_appointment task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Kill any existing MedinTux instance
pkill -f "Manager.exe" 2>/dev/null || true
pkill -f "wine" 2>/dev/null || true
sleep 3

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 2

# Ensure patient MARTIN Sophie exists in the real MedinTux schema
# Real tables: IndexNomPrenom + fchpat (NOT Personnes)
MARTIN_COUNT=$(mysql -u root DrTuxTest -N -e \
    "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_NomDos='MARTIN' AND FchGnrl_Prenom='Sophie'" \
    2>/dev/null || echo 0)

if [ "$MARTIN_COUNT" -eq 0 ]; then
    echo "Inserting patient MARTIN Sophie..."
    GUID="$(cat /proc/sys/kernel/random/uuid | tr '[:lower:]' '[:upper:]')"
    mysql -u root DrTuxTest -e \
        "INSERT IGNORE INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) \
         VALUES ('$GUID', 'MARTIN', 'Sophie', 'Dossier')" 2>/dev/null || true
    mysql -u root DrTuxTest -e \
        "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe, FchPat_Titre, \
         FchPat_Adresse, FchPat_CP, FchPat_Ville, FchPat_Tel1, FchPat_NumSS) \
         VALUES ('$GUID', 'MARTIN', '1985-03-22', 'F', 'Mme', '45 Avenue des Fleurs', 69001, 'Lyon', \
         '04.72.11.22.33', '2850369001022')" 2>/dev/null || true
fi

echo "Patient MARTIN Sophie verified in database."

# Launch MedinTux Manager (extracts Qt DLLs if needed, waits for window)
launch_medintux_manager

echo "=== schedule_appointment task setup complete ==="
echo "Task: Schedule appointment for MARTIN Sophie on 2026-03-16 at 10:00 in MedinTux agenda"
