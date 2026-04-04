#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: create_accounting_journal ==="

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Wait for Ekylibre to be ready
wait_for_ekylibre 120

# 3. Clean up any existing journal with the target code 'SUBV' to ensure a fresh start
echo "Cleaning up any existing SUBV journal..."
ekylibre_db_query "DELETE FROM journals WHERE code = 'SUBV';"

# 4. Record initial journal count
INITIAL_COUNT=$(ekylibre_db_query "SELECT COUNT(*) FROM journals;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_journal_count.txt
echo "Initial journal count: $INITIAL_COUNT"

# 5. Open Firefox to the Ekylibre Dashboard (User starts navigation from here)
EKYLIBRE_URL=$(detect_ekylibre_url)
# Navigate to backend root to ensure agent has to find the menu
ensure_firefox_with_ekylibre "$EKYLIBRE_URL/backend"
maximize_firefox

sleep 5

# 6. Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="