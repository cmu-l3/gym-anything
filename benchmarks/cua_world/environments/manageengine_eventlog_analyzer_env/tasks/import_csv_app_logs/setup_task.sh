#!/bin/bash
# Setup for "import_csv_app_logs" task

echo "=== Setting up Import CSV Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Generate the CSV file with realistic legacy data
# We use dates that are recent enough to be accepted if there's a window, 
# but fixed enough relative to "now" if possible. 
# For safety, we use yesterday's date to avoid "future" errors or "too old" retention policies.
YESTERDAY=$(date -d "yesterday" '+%Y-%m-%d')

mkdir -p /home/ga/Documents
CSV_FILE="/home/ga/Documents/payroll_logs.csv"

cat > "$CSV_FILE" << EOF
Date,Host,User,Severity,EventID,Message
${YESTERDAY} 08:00:01,PAYROLL-DB,system,INFO,100,Batch processing started for Q3
${YESTERDAY} 08:15:22,PAYROLL-DB,admin,WARNING,300,High memory usage detected
${YESTERDAY} 08:30:45,PAYROLL-DB,system,ERROR,500,Database connection lost during batch processing
${YESTERDAY} 08:31:00,PAYROLL-DB,system,INFO,101,Retrying connection attempt 1
${YESTERDAY} 09:00:00,PAYROLL-DB,system,INFO,102,Batch processing completed with errors
EOF

chown ga:ga "$CSV_FILE"
echo "Created $CSV_FILE"

# 2. Record Initial State
# Count events containing "PAYROLL-DB" to ensure we start from zero
INITIAL_COUNT=$(ela_db_query "SELECT COUNT(*) FROM SystemLog WHERE MESSAGE LIKE '%PAYROLL-DB%'" 2>/dev/null | grep -o "[0-9]*" || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_payroll_count.txt

# Record start time
date +%s > /tmp/task_start_time.txt

# 3. Prepare Environment
wait_for_eventlog_analyzer

# Open Firefox to the Import page (or Settings if deep link fails, but let's try Settings)
# /event/index.do#/settings/import-log-data is a likely path, but generic dashboard is safer
ensure_firefox_on_ela "/event/AppsHome.do#/home/dashboard/0"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="