#!/bin/bash
# Setup script for Analytical Window Queries task
# Ensures Oracle is ready and cleans up previous output files

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Analytical Window Queries Task ==="

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous artifacts
echo "Cleaning up Desktop..."
rm -f /home/ga/Desktop/salary_percentiles.txt
rm -f /home/ga/Desktop/dept_budget_analysis.txt
rm -f /home/ga/Desktop/turnover_risk.txt
rm -f /home/ga/Desktop/salary_pivot.txt
rm -f /home/ga/Desktop/analytical_queries.sql

# 3. Verify Oracle DB connectivity
echo "Verifying Database..."
if ! wait_for_oracle 60; then
    echo "ERROR: Oracle Database not ready"
    exit 1
fi

# 4. Verify HR Schema has data (approx 107 rows)
COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM employees;" "hr")
echo "Employee count: $COUNT"
if [ "$COUNT" -lt 100 ]; then
    echo "ERROR: HR Schema seems empty or inaccessible."
    exit 1
fi

# 5. Open a terminal for the agent (standard entry point for SQL tools)
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=100x30 &"
    sleep 2
fi

# 6. Capture initial state screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="