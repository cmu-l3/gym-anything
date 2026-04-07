#!/bin/bash
echo "=== Setting up generate_web_to_lead_form task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming (file must be created AFTER this)
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# 2. Setup local filesystem target directory
echo "Preparing local filesystem..."
mkdir -p /home/ga/Documents
# Remove the target file if it exists from a previous run to ensure a clean state
rm -f /home/ga/Documents/tradeshow_lead_form.html 2>/dev/null || true
chown ga:ga /home/ga/Documents

# 3. Ensure logged in and navigate to Home dashboard
# The agent will need to navigate to Campaigns from here.
echo "Ensuring SuiteCRM is logged in..."
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"
sleep 3

# 4. Take initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/generate_web_to_lead_form_initial.png

echo "=== generate_web_to_lead_form task setup complete ==="
echo "Task: Generate a Web-to-Lead form with a specific redirect URL and save it to the OS."