#!/bin/bash
# Setup script for Register Worker task
# - Cleans up previous runs (removes Marie Dupont if exists)
# - Records initial worker count
# - Opens Firefox to Dashboard

set -e
echo "=== Setting up Register Worker Task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Wait for Ekylibre
wait_for_ekylibre 120
EKYLIBRE_URL=$(detect_ekylibre_url)

# 3. Clean up any existing worker named "Marie Dupont" to ensure clean state
echo "Cleaning up previous 'Marie Dupont' records..."
ekylibre_db_query "DELETE FROM products WHERE type = 'Worker' AND (name ILIKE '%Marie%Dupont%' OR name ILIKE '%Dupont%Marie%');" 2>/dev/null || true

# 4. Record initial worker count for anti-gaming verification
INITIAL_COUNT=$(ekylibre_db_query "SELECT COUNT(*) FROM products WHERE type = 'Worker';" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_worker_count.txt
echo "Initial worker count: $INITIAL_COUNT"

# 5. Start Firefox on the Backend Dashboard (forcing agent to navigate to Workers)
# We start at the main backend page so the agent must find "Workers" in the menu.
START_URL="${EKYLIBRE_URL}/backend"
ensure_firefox_with_ekylibre "$START_URL"
sleep 5
maximize_firefox

# 6. Capture initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Target: Create worker 'Marie Dupont' (born 1992-06-15)"
echo "Starting at: $START_URL"