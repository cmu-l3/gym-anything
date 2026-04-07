#!/bin/bash
set -e
echo "=== Setting up configure_practitioner_accounts task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
echo "Starting MySQL..."
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 3

# Wait for MySQL readiness
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        echo "MySQL is ready"
        break
    fi
    sleep 1
done

# Clean up any existing target users to ensure a clean start
# We check common table names for users in MedinTux schemas or generic names
echo "Cleaning up target users..."
TARGET_LOGINS="'mlefebvre', 'smartin'"

# List of potential tables to clean
POTENTIAL_TABLES=("Personnes" "utilisateurs" "users" "praticiens" "medecins" "Droits")

for tbl in "${POTENTIAL_TABLES[@]}"; do
    # Check if table exists
    if mysql -u root DrTuxTest -e "DESCRIBE $tbl" >/dev/null 2>&1; then
        # Try to delete by common login column names
        mysql -u root DrTuxTest -e "DELETE FROM $tbl WHERE FchGnrl_Login IN ($TARGET_LOGINS)" 2>/dev/null || true
        mysql -u root DrTuxTest -e "DELETE FROM $tbl WHERE Login IN ($TARGET_LOGINS)" 2>/dev/null || true
        mysql -u root DrTuxTest -e "DELETE FROM $tbl WHERE login IN ($TARGET_LOGINS)" 2>/dev/null || true
        mysql -u root DrTuxTest -e "DELETE FROM $tbl WHERE nom_login IN ($TARGET_LOGINS)" 2>/dev/null || true
    fi
done

# Remove any previous report file
rm -f /home/ga/practitioner_report.txt

# Launch MedinTux Manager to provide context/GUI if the agent wants to explore that way
# (Though the task is DB-focused, the app should be running)
echo "Launching MedinTux Manager..."
launch_medintux_manager 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="