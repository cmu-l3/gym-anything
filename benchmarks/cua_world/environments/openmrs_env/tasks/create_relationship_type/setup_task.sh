#!/bin/bash
# Setup script for create_relationship_type task
# Cleans up any existing "Research Coordinator" relationship types and logs in the agent.

set -e
echo "=== Setting up create_relationship_type task ==="
source /workspace/scripts/task_utils.sh

# 1. Record Task Start Time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Clean up: Delete any pre-existing relationship type with these names
# This ensures the agent must actually create it, not just find an existing one.
echo "Cleaning up potential pre-existing metadata..."
omrs_db_query "DELETE FROM relationship_type WHERE a_is_to_b = 'Research Coordinator' OR b_is_to_a = 'Research Participant';"

# 3. Record initial count (should be 0 for this specific type)
INITIAL_CHECK=$(omrs_db_query "SELECT count(*) FROM relationship_type WHERE a_is_to_b = 'Research Coordinator';" | tail -n 1)
echo "$INITIAL_CHECK" > /tmp/initial_count.txt
echo "Initial count of target relationship type: $INITIAL_CHECK"

# 4. Ensure OpenMRS is accessible and logged in
# We start at the home page. The agent must find their way to Admin > Metadata.
echo "Launching Firefox..."
ensure_openmrs_logged_in "http://localhost/openmrs/spa/home"

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="