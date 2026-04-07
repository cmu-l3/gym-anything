#!/bin/bash
set -e
echo "=== Setting up establish_document_relations task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Nuxeo to be ready
wait_for_nuxeo 120

# ---------------------------------------------------------------------------
# Ensure required documents exist
# ---------------------------------------------------------------------------
echo "Verifying prerequisite documents..."

# Helper to create placeholder if missing
ensure_doc() {
    local path="$1"
    local type="$2"
    local title="$3"
    
    if ! doc_exists "$path"; then
        echo "  Creating missing document: $path"
        local parent=$(dirname "$path")
        local name=$(basename "$path")
        # Ensure parent exists (recursive check simplified for this task)
        if ! doc_exists "$parent"; then
            echo "  Warning: Parent $parent missing, cannot create $name"
            return
        fi
        
        create_doc_if_missing "$parent" "$type" "$name" "$title" "Restored for task"
    else
        echo "  OK: $path"
    fi
}

# Ensure workspaces exist
ensure_doc "/default-domain/workspaces/Projects" "Workspace" "Projects"
ensure_doc "/default-domain/workspaces/Templates" "Workspace" "Templates"

# Ensure files exist
ensure_doc "/default-domain/workspaces/Projects/Annual-Report-2023" "File" "Annual Report 2023"
ensure_doc "/default-domain/workspaces/Projects/Project-Proposal" "File" "Project Proposal"
ensure_doc "/default-domain/workspaces/Projects/Q3-Status-Report" "File" "Q3 Status Report"
ensure_doc "/default-domain/workspaces/Templates/Contract-Template" "File" "Contract Template"

# ---------------------------------------------------------------------------
# Clear any existing relations (Clean State)
# ---------------------------------------------------------------------------
echo "Clearing existing relations..."
# Note: Nuxeo doesn't have a simple "clear all relations" API endpoint without
# iterating ID by ID. For this task setup, we will record the initial state
# to ensure we don't give credit for pre-existing relations, although
# the environment should be clean.

# ---------------------------------------------------------------------------
# Record Initial State (Anti-Gaming)
# ---------------------------------------------------------------------------
echo "Recording initial relation counts..."
python3 - <<'PYEOF'
import requests, json

NUXEO = "http://localhost:8080/nuxeo"
AUTH = ("Administrator", "Administrator")

docs = {
    "Annual-Report-2023": "/default-domain/workspaces/Projects/Annual-Report-2023",
    "Contract-Template": "/default-domain/workspaces/Templates/Contract-Template"
}

initial_state = {}

for name, path in docs.items():
    try:
        # Check outgoing relations
        r = requests.get(
            f"{NUXEO}/api/v1/path{path}/@relations",
            auth=AUTH,
            headers={"Content-Type": "application/json"},
            timeout=10
        )
        if r.status_code == 200:
            data = r.json()
            # Count relations
            initial_state[name] = len(data.get("entries", []))
        else:
            initial_state[name] = 0
    except Exception:
        initial_state[name] = 0

with open("/tmp/initial_relations_count.json", "w") as f:
    json.dump(initial_state, f)
print(f"Initial state: {json.dumps(initial_state)}")
PYEOF

# Remove any pre-existing report file
rm -f /home/ga/nuxeo_relations_report.txt

# ---------------------------------------------------------------------------
# Browser Setup
# ---------------------------------------------------------------------------
# Open Firefox to the Projects workspace
open_nuxeo_url "http://localhost:8080/nuxeo/ui/#!/browse/default-domain/workspaces/Projects" 10
nuxeo_login

# Navigate explicitly to ensure correct view
navigate_to "http://localhost:8080/nuxeo/ui/#!/browse/default-domain/workspaces/Projects"

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="