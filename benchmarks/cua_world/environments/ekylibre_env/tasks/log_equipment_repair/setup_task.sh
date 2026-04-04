#!/bin/bash
set -e
echo "=== Setting up task: log_equipment_repair@1 ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Ekylibre to be ready
wait_for_ekylibre 120

# 2. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# 3. Record initial state (Intervention count)
# We use docker exec to query the DB directly
echo "Recording initial intervention count..."
INITIAL_COUNT=$(ekylibre_db_query "SELECT count(*) FROM interventions")
echo "${INITIAL_COUNT:-0}" > /tmp/initial_count.txt
echo "Initial intervention count: ${INITIAL_COUNT:-0}"

# 4. Ensure Firefox is running and logged in
# We start at the Dashboard to force navigation
EKYLIBRE_URL=$(detect_ekylibre_url)
ensure_firefox_with_ekylibre "$EKYLIBRE_URL"

# 5. Maximize window for best visibility
maximize_firefox

# 6. Capture initial state screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="