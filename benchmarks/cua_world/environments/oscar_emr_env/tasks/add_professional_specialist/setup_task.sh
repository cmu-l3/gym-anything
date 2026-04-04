#!/bin/bash
echo "=== Setting up add_professional_specialist task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Wait for OSCAR to be ready (critical for DB access)
wait_for_oscar_http 180

# Clean up any previous attempts (idempotency)
# We delete any specialist with this specific name to ensure a clean slate
echo "Cleaning up any existing record for Rajesh Patel..."
oscar_query "DELETE FROM professionalSpecialists WHERE firstName='Rajesh' AND lastName='Patel'" 2>/dev/null || true

# Record initial specialist count
INITIAL_COUNT=$(oscar_query "SELECT COUNT(*) FROM professionalSpecialists" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt
echo "Initial specialist count: $INITIAL_COUNT"

# Ensure Firefox is open on the login page
ensure_firefox_on_oscar

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="