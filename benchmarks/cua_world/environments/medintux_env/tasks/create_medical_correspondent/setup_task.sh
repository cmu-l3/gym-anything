#!/bin/bash
echo "=== Setting up Create Medical Correspondent Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 2

# Clean state: Remove the target correspondent if they already exist
# Correspondents are stored in the 'Personnes' table in DrTuxTest
echo "Ensuring clean state (removing existing MARTIN Sophie)..."
mysql -u root DrTuxTest -e "DELETE FROM Personnes WHERE Nom='MARTIN' AND Prenom='Sophie'" 2>/dev/null || true

# Record initial count of people/correspondents
INITIAL_COUNT=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM Personnes" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt

# Launch MedinTux Manager
# This utility function (from task_utils.sh) handles Wine setup, DLLs, and window waiting
launch_medintux_manager

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Add Dr. Sophie MARTIN (Cardiologue, Toulouse, 31300) to correspondents."