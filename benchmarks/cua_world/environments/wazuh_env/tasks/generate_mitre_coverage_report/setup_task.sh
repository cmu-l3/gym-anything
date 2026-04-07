#!/bin/bash
set -e
echo "=== Setting up MITRE Coverage Report Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any previous reports to ensure a fresh start
rm -rf /home/ga/reports
mkdir -p /home/ga/reports
chown ga:ga /home/ga/reports

# Verify Wazuh API is accessible (wait if necessary)
echo "Checking Wazuh API availability..."
for i in {1..30}; do
    if check_api_health; then
        echo "Wazuh API is healthy."
        break
    fi
    echo "Waiting for Wazuh API..."
    sleep 2
done

# Ensure MITRE database in Wazuh is ready (usually pre-loaded, but good to check)
TOKEN=$(get_api_token)
if [ -n "$TOKEN" ]; then
    echo "Verifying MITRE database access..."
    wazuh_api GET "/mitre/techniques?limit=1" > /dev/null && echo "MITRE API accessible." || echo "WARNING: MITRE API check failed."
else
    echo "WARNING: Could not obtain API token during setup."
fi

# Ensure jq is installed (should be from install_wazuh.sh, but verifying)
if ! command -v jq &> /dev/null; then
    apt-get update && apt-get install -y jq
fi

# We don't need to open a browser for this task as it's API/CLI based,
# but we'll ensure the environment is clean.

echo "=== Task setup complete ==="