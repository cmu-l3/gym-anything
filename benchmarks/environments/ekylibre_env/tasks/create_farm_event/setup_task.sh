#!/bin/bash
set -e
echo "=== Setting up create_farm_event task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Wait for Ekylibre to be accessible
wait_for_ekylibre 120

# Record initial event count
INITIAL_COUNT=$(ekylibre_db_query "SELECT COUNT(*) FROM events;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_event_count.txt
echo "Initial event count: $INITIAL_COUNT"

# Detect the working URL
EKYLIBRE_LIVE_URL=$(detect_ekylibre_url)
echo "Ekylibre URL: $EKYLIBRE_LIVE_URL"

# Open Firefox to the Ekylibre dashboard (agent must navigate to events themselves)
ensure_firefox_with_ekylibre "${EKYLIBRE_LIVE_URL}/backend"
sleep 5
maximize_firefox
sleep 2

# Take initial state screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved."

echo "=== Task setup complete ==="