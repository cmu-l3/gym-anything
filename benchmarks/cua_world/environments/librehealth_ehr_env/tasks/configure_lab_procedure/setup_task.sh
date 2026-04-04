#!/bin/bash
echo "=== Setting up Configure Lab Procedure Task ==="

source /workspace/scripts/task_utils.sh

# Ensure LibreHealth EHR is running
wait_for_librehealth 120

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial database state for anti-gaming
# We track the maximum procedure_type_id to ensure new records are created
MAX_ID=$(librehealth_query "SELECT MAX(procedure_type_id) FROM procedure_type" 2>/dev/null)
if [ -z "$MAX_ID" ] || [ "$MAX_ID" = "NULL" ]; then
    MAX_ID=0
fi
echo "$MAX_ID" > /tmp/initial_max_id.txt
echo "Initial Max Procedure ID: $MAX_ID"

# Clean up any previous attempts (idempotency for development)
# We delete by name to ensure a clean slate if the task is retried
librehealth_query "DELETE FROM procedure_type WHERE name IN ('In-House Lab', 'Comprehensive Metabolic Panel', 'Glucose', 'Creatinine', 'Sodium') AND procedure_type_id > $MAX_ID" 2>/dev/null || true

# Start Firefox at the Dashboard
restart_firefox "http://localhost:8000/interface/main/tabs/main.php"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="