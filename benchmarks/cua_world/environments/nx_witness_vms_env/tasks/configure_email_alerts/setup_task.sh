#!/bin/bash
set -e
echo "=== Setting up configure_email_alerts task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Firefox is closed (this is an API task, UI not required/distracting)
pkill -f firefox 2>/dev/null || true

# Refresh auth token to ensure we can communicate
refresh_nx_token > /dev/null

# 1. Reset SMTP settings to a clean state (empty/default)
# This prevents "do nothing" agents from succeeding if values happened to be there
echo "Resetting SMTP settings to defaults..."
RESET_PAYLOAD='{
  "smtpHost": "",
  "smtpPort": 0,
  "smtpUser": "",
  "smtpPassword": "",
  "emailFrom": "",
  "smtpConnectionType": "insecure",
  "smtpName": ""
}'

nx_api_patch "/rest/v1/system/settings" "$RESET_PAYLOAD" > /tmp/reset_response.json 2>&1

# 2. Verify reset was successful
CURRENT_SETTINGS=$(nx_api_get "/rest/v1/system/settings")
HOST_CHECK=$(echo "$CURRENT_SETTINGS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('smtpHost', ''))" 2>/dev/null)

if [ -z "$HOST_CHECK" ]; then
    echo "SMTP settings successfully cleared."
else
    echo "WARNING: Failed to clear SMTP settings. Task verification may be affected."
fi

# 3. Create a helpful hint file for the agent? 
# No, the description is sufficient. But we ensure the admin user works.
echo "Verifying admin access..."
nx_api_get "/rest/v1/users" > /dev/null && echo "Admin access confirmed."

# 4. Take initial screenshot (likely empty desktop or terminal)
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="