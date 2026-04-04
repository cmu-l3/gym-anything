#!/bin/bash
set -e
echo "=== Setting up create_data_asset task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Record initial count of data assets
# Note: Eramba table names are usually pluralized snake_case.
# We check 'data_assets' table.
INITIAL_COUNT=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM data_assets WHERE deleted=0;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_data_asset_count.txt
echo "Initial data asset count: $INITIAL_COUNT"

# 3. Ensure Eramba is running and accessible
# (Already handled by env setup, but good to double check)
if ! docker ps | grep -q eramba-app; then
    echo "Error: Eramba container not running"
    exit 1
fi

# 4. Launch Firefox and login/navigate
# We navigate to the dashboard to force the agent to find the Asset Management module
ensure_firefox_eramba "http://localhost:8080/dashboard"

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="