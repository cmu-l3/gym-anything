#!/bin/bash
echo "=== Setting up Household Aggregation Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 2

# Cleanup: Remove these specific patients if they exist from previous runs to ensure clean state
# We delete by name patterns to be safe
echo "Cleaning up previous data..."
mysql -u root DrTuxTest -e "DELETE FROM fchpat WHERE FchPat_NomFille IN ('LEMOINE', 'DUPUIS', 'MARTIN') AND FchPat_Ville IN ('Paris', 'PARIS', 'Lyon', 'Strasbourg');" 2>/dev/null || true
mysql -u root DrTuxTest -e "DELETE FROM IndexNomPrenom WHERE FchGnrl_NomDos IN ('LEMOINE', 'DUPUIS', 'MARTIN');" 2>/dev/null || true

# Ensure target directory exists
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/household_mailing_list.csv

# Launch MedinTux Manager (in case agent wants to use GUI for Part 1)
# We use the utility function that handles Qt DLLs and window waiting
launch_medintux_manager

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="