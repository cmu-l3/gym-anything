#!/bin/bash
# Setup script for create_chart_account task
# Goal: Ensure clean state (account 6227 does not exist) and start Ekylibre

echo "=== Setting up create_chart_account task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 1. Clean up: Delete account 6227 if it already exists
# This ensures that if the agent succeeds, they actually created it.
echo "Cleaning up any existing account 6227..."
docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -c "DELETE FROM accounts WHERE number = '6227';" >/dev/null 2>&1 || true

# 2. Record initial account count
echo "Recording initial account count..."
INITIAL_COUNT=$(ekylibre_db_query "SELECT COUNT(*) FROM accounts")
echo "$INITIAL_COUNT" > /tmp/initial_account_count.txt
echo "Initial accounts: $INITIAL_COUNT"

# 3. Wait for Ekylibre
wait_for_ekylibre 120
EKYLIBRE_URL=$(detect_ekylibre_url)

# 4. Open Firefox at the Dashboard (Agent must navigate to Accounting)
# We purposely land on the dashboard to test navigation skills.
TARGET_URL="${EKYLIBRE_URL}/backend"
ensure_firefox_with_ekylibre "$TARGET_URL"
sleep 5

# 5. Maximize window for visibility
maximize_firefox

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Create account 6227 'Frais de certification biologique'"