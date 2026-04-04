#!/bin/bash
set -e
echo "=== Setting up create_fixed_asset task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Ekylibre to be ready
wait_for_ekylibre 120

# Record initial fixed asset count for anti-gaming
echo "Recording initial fixed asset count..."
INITIAL_COUNT=$(ekylibre_db_query "SELECT COUNT(*) FROM fixed_assets;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_fixed_asset_count.txt
echo "Initial fixed asset count: $INITIAL_COUNT"

# Ensure Firefox is open on Ekylibre dashboard
# We start at the dashboard so the agent has to navigate to Accounting > Fixed Assets
URL=$(detect_ekylibre_url)
ensure_firefox_with_ekylibre "${URL}/backend"
sleep 5

# Maximize window
maximize_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="