#!/bin/bash
echo "=== Setting up add_patient task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Kill any existing MedinTux instance
pkill -f "Manager.exe" 2>/dev/null || true
pkill -f "wine" 2>/dev/null || true
sleep 3

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 2

# Remove ROUSSEAU Laurent if he already exists (clean state for the add_patient task)
# Uses the real MedinTux schema: IndexNomPrenom + fchpat
EXISTING_GUID=$(mysql -u root DrTuxTest -N -e \
    "SELECT FchGnrl_IDDos FROM IndexNomPrenom WHERE FchGnrl_NomDos='ROUSSEAU' AND FchGnrl_Prenom='Laurent' LIMIT 1" \
    2>/dev/null || echo "")
if [ -n "$EXISTING_GUID" ]; then
    echo "Removing existing ROUSSEAU Laurent (GUID: $EXISTING_GUID)..."
    mysql -u root DrTuxTest -e \
        "DELETE FROM fchpat WHERE FchPat_GUID_Doss='$EXISTING_GUID';" \
        2>/dev/null || true
    mysql -u root DrTuxTest -e \
        "DELETE FROM IndexNomPrenom WHERE FchGnrl_IDDos='$EXISTING_GUID';" \
        2>/dev/null || true
fi

# Count existing patients for reference
PATIENT_COUNT=$(mysql -u root DrTuxTest -N -e \
    "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_Type='Dossier'" 2>/dev/null || echo "unknown")
echo "Current patient count (after cleanup): $PATIENT_COUNT"

# Launch MedinTux Manager (extracts Qt DLLs if needed, waits for window)
launch_medintux_manager

echo "=== add_patient task setup complete ==="
echo "Task: Register new patient ROUSSEAU Laurent in MedinTux"
