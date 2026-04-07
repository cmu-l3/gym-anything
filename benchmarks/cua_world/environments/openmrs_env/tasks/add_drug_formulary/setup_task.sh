#!/bin/bash
# Setup: add_drug_formulary task
# Ensures the target drug does NOT exist in the database before starting.

echo "=== Setting up add_drug_formulary task ==="
source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 1. Clean up: Delete the drug if it already exists (Hard delete from DB to ensure clean 'Create' workflow)
echo "Ensuring 'Aspirin 500mg ES' does not exist..."
TARGET_DRUG="Aspirin 500mg ES"

# We use direct DB query to ensure it's gone, as REST API might only retire it
# Note: Using omrs_db_query helper from task_utils
omrs_db_query "DELETE FROM drug WHERE name = '$TARGET_DRUG';" 2>/dev/null || true

# Verify it's gone
CHECK_EXISTS=$(omrs_db_query "SELECT count(*) FROM drug WHERE name = '$TARGET_DRUG';" 2>/dev/null || echo "0")
if [ "$CHECK_EXISTS" != "0" ]; then
    echo "WARNING: Failed to delete existing drug. Task verification might be affected."
else
    echo "Clean state confirmed: Drug '$TARGET_DRUG' not found."
fi

# 2. Ensure Admin is logged in and browser is ready
# We start at the Home page, agent must navigate to System Admin
echo "Launching Firefox..."
ensure_openmrs_logged_in "http://localhost/openmrs/spa/home"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo ""
echo "=== add_drug_formulary setup complete ==="
echo "Task: Create drug '$TARGET_DRUG' linked to concept 'Aspirin' with strength 500."