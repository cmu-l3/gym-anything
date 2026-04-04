#!/bin/bash
set -e
echo "=== Setting up Add Custom Drug Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Wait for OSCAR to be ready
wait_for_oscar_http 180

# ============================================================
# 1. Clean up any existing records for this drug
# ============================================================
echo "Cleaning up any previous entries for 'Menthol 1% Cream'..."
# We delete by name to ensure the agent creates it fresh.
# Note: In a real prod env we wouldn't delete, but this is a sandbox.
oscar_query "DELETE FROM drug WHERE brand_name LIKE 'Menthol 1% Cream%' OR brand_name LIKE 'Menthol 1% in Aqueous%';" 2>/dev/null

# ============================================================
# 2. Record initial count of similar drugs (for debugging/verification)
# ============================================================
INITIAL_COUNT=$(oscar_query "SELECT COUNT(*) FROM drug WHERE generic_name LIKE '%Menthol%'" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_menthol_count.txt
echo "Initial Menthol drug count: $INITIAL_COUNT"

# ============================================================
# 3. Launch Firefox on Login Page
# ============================================================
ensure_firefox_on_oscar

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="