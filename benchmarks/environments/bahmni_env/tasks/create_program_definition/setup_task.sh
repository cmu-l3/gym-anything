#!/bin/bash
set -u

echo "=== Setting up Create Program Definition Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure Bahmni/OpenMRS is reachable
if ! wait_for_bahmni 600; then
    echo "ERROR: Bahmni is not reachable"
    exit 1
fi

# Clean state: Check if Program or Concept already exists and warn/fail if so.
# In a clean environment, they shouldn't exist. If they do, we try to retire them
# or just note it for the verifier (verifier checks creation timestamp).

echo "Checking for existing data..."

# Check Program
EXISTING_PROG=$(openmrs_api_get "/program?q=Nutrition+Support&v=default")
PROG_COUNT=$(echo "$EXISTING_PROG" | python3 -c "import sys, json; print(len(json.load(sys.stdin).get('results', [])))" 2>/dev/null || echo "0")

if [ "$PROG_COUNT" -gt "0" ]; then
    echo "WARNING: Program 'Nutrition Support' already exists. This might affect verification if not cleaned."
    # Attempt to retire/purge would go here, but OpenMRS REST API purge is complex.
    # We rely on timestamp verification.
fi

# Record initial counts
INITIAL_PROG_JSON=$(openmrs_api_get "/program?v=default")
INITIAL_PROG_COUNT=$(echo "$INITIAL_PROG_JSON" | python3 -c "import sys, json; print(len(json.load(sys.stdin).get('results', [])))" 2>/dev/null || echo "0")
echo "$INITIAL_PROG_COUNT" > /tmp/initial_program_count.txt

# Start Browser at OpenMRS Admin page
# We use the legacy admin UI for this task
OPENMRS_ADMIN_URL="${OPENMRS_BASE_URL}/admin"

echo "Starting browser at $OPENMRS_ADMIN_URL..."
if ! start_browser "$OPENMRS_ADMIN_URL" 4; then
    echo "ERROR: Browser failed to start"
    exit 1
fi

focus_browser || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="