#!/bin/bash
set -e
echo "=== Setting up Create Vendor Questionnaire task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Ensure Firefox is running and logged into Eramba
# We navigate to the Online Assessments index if possible, or dashboard
ensure_firefox_eramba "http://localhost:8080/questionnaires/index"
sleep 5

# 3. Record initial state (count of questionnaires)
# This helps us detect if a new one was actually created vs just finding an old one
INITIAL_COUNT=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "SELECT COUNT(*) FROM questionnaires WHERE deleted=0;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_questionnaire_count.txt

# 4. Maximize window for better agent visibility
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "Setup complete. Initial questionnaire count: $INITIAL_COUNT"