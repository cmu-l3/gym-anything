#!/bin/bash
echo "=== Setting up add_multiple_patients task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 2

# CLEAN STATE: Remove any existing MOREAU patients to prevent ambiguity
echo "Cleaning up any existing MOREAU records..."
# Get GUIDs to delete from fchpat
GUIDS=$(mysql -u root DrTuxTest -N -e "SELECT FchGnrl_IDDos FROM IndexNomPrenom WHERE FchGnrl_NomDos='MOREAU'" 2>/dev/null)

if [ -n "$GUIDS" ]; then
    echo "$GUIDS" | while read -r guid; do
        if [ -n "$guid" ]; then
            mysql -u root DrTuxTest -e "DELETE FROM fchpat WHERE FchPat_GUID_Doss='$guid'" 2>/dev/null || true
            mysql -u root DrTuxTest -e "DELETE FROM IndexNomPrenom WHERE FchGnrl_IDDos='$guid'" 2>/dev/null || true
        fi
    done
fi

# Double check clean state
REMAINING=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_NomDos='MOREAU'" 2>/dev/null || echo 0)
echo "Remaining MOREAU records: $REMAINING" > /tmp/initial_moreau_count.txt

# Record total initial patient count
INITIAL_COUNT=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_Type='Dossier'" 2>/dev/null || echo 0)
echo "$INITIAL_COUNT" > /tmp/initial_total_patient_count.txt

# Ensure MedinTux Manager is running
launch_medintux_manager

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="