#!/bin/bash
# Pre-task setup for aggregate_project_budgets
# Generates random budget data, creates project documents, and sets up the environment.

set -e
echo "=== Setting up aggregate_project_budgets task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Nuxeo to be ready
wait_for_nuxeo 180

# 2. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 3. Generate Random Budgets
# Generate 3 random integers between 15,000 and 85,000
B1=$((15000 + RANDOM % 70000))
B2=$((15000 + RANDOM % 70000))
B3=$((15000 + RANDOM % 70000))
TOTAL=$((B1 + B2 + B3))

# Save ground truth for verification (hidden from agent)
# This file will be retrieved by the verifier using copy_from_env
echo "$TOTAL" > /tmp/budget_ground_truth.txt
chmod 644 /tmp/budget_ground_truth.txt
echo "Generated budgets: $B1, $B2, $B3. Total: $TOTAL"

# 4. Create Folder Structure
echo "Creating Q3-Infrastructure folder..."
# Clean up if exists from previous run
if doc_exists "/default-domain/workspaces/Projects/Q3-Infrastructure"; then
    # We delete it to ensure a clean state with new numbers
    UID=$(nuxeo_api GET "/path/default-domain/workspaces/Projects/Q3-Infrastructure" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))")
    if [ -n "$UID" ]; then
        nuxeo_api DELETE "/id/$UID" > /dev/null
    fi
fi
sleep 2

create_doc_if_missing "/default-domain/workspaces/Projects" "Folder" "Q3-Infrastructure" "Q3 Infrastructure Projects" "Portfolio for Q3 Infrastructure works"

# 5. Create Project Documents with Budgets in Description
# We use a helper function to keep it clean
create_project_doc() {
    local name="$1"
    local title="$2"
    local budget="$3"
    local desc="Status: Active. Department: Civil Engineering. Budget: $budget USD. Priority: High."
    local parent="/default-domain/workspaces/Projects/Q3-Infrastructure"
    
    # Create the document payload
    local payload
    payload=$(cat <<EOFJSON
{
  "entity-type": "document",
  "type": "File",
  "name": "$name",
  "properties": {
    "dc:title": "$title",
    "dc:description": "$desc"
  }
}
EOFJSON
)
    nuxeo_api POST "/path$parent/" "$payload" > /dev/null
    echo "Created $name with budget $budget"
}

create_project_doc "Project-Alpha" "Project Alpha - Bridge Renovation" "$B1"
create_project_doc "Project-Beta" "Project Beta - Road Resurfacing" "$B2"
create_project_doc "Project-Gamma" "Project Gamma - Lighting Upgrade" "$B3"

# 6. Ensure no pre-existing solution exists
if doc_exists "/default-domain/workspaces/Projects/Q3-Infrastructure/Budget-Summary"; then
    nuxeo_api DELETE "/path/default-domain/workspaces/Projects/Q3-Infrastructure/Budget-Summary" > /dev/null
fi

# 7. Prepare Firefox
# Open Nuxeo directly to the folder to start the agent in the right context
TARGET_URL="$NUXEO_UI/#!/browse/default-domain/workspaces/Projects/Q3-Infrastructure"
open_nuxeo_url "$NUXEO_URL/login.jsp" 8

# Login
nuxeo_login

# Navigate to the specific folder
navigate_to "$TARGET_URL"

# 8. Capture Initial State
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="