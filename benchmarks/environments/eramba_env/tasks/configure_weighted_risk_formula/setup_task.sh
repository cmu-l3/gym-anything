#!/bin/bash
echo "=== Setting up configure_weighted_risk_formula task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Eramba and Firefox are running
ensure_firefox_eramba "http://localhost:8080/dashboard/dashboard"
sleep 5

# 2. Record initial state of the Risk Calculation formula
# We need to know what it was before to prove it changed
echo "Recording initial database state..."
INITIAL_FORMULA=$(eramba_db_query "SELECT calculation FROM risk_calculations WHERE model='Risks' LIMIT 1;" 2>/dev/null)
echo "$INITIAL_FORMULA" > /tmp/initial_formula.txt

# 3. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Current Formula: $INITIAL_FORMULA"
echo "Target Formula: likelihood + (2 * impact)"