#!/bin/bash
echo "=== Setting up create_concept_class task ==="
source /workspace/scripts/task_utils.sh

# 1. Record task start time (critical for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Clean state: Remove 'SDOH' concept class if it exists
echo "Cleaning up any existing 'SDOH' concept class..."
omrs_db_query "DELETE FROM concept_class WHERE name = 'SDOH';" 
# Reset auto-increment or cache if needed (usually not strictly necessary for this table, but good practice to flush)
# We can't easily flush Hibernate cache from here, but direct DB deletion is usually reflected after page reload.

# 3. Record initial state count
INITIAL_COUNT=$(omrs_db_query "SELECT COUNT(*) FROM concept_class;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt
echo "Initial concept class count: $INITIAL_COUNT"

# 4. Launch Browser and Login
# The Agent starts at the home page, but we ensure they are logged in.
ensure_openmrs_logged_in "http://localhost/openmrs/spa/home"

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="