#!/bin/bash
echo "=== Setting up export_filtered_leads_to_csv task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Clean up any existing CSV files to ensure a clean slate
rm -f /home/ga/healthcare_leads.csv 2>/dev/null || true
rm -f /home/ga/Downloads/*.csv 2>/dev/null || true

# 3. Ensure the database has exactly 18 "Healthcare" leads for the scenario
echo "Injecting exact scenario data constraints (18 Healthcare leads)..."
# First set all leads to something else (e.g., 'Technology')
docker exec vtiger-db mysql -u vtiger -pvtiger_pass vtiger -e "UPDATE vtiger_leaddetails SET industry='Technology';"
# Then set exactly 18 leads to 'Healthcare'
docker exec vtiger-db mysql -u vtiger -pvtiger_pass vtiger -e "UPDATE vtiger_leaddetails SET industry='Healthcare' ORDER BY leadid LIMIT 18;"

# 4. Ensure logged in and navigate to Leads list view
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Leads&view=List"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/export_leads_initial.png

echo "=== export_filtered_leads_to_csv task setup complete ==="
echo "Task: Filter leads by 'Healthcare', export selected to CSV, save as /home/ga/healthcare_leads.csv"