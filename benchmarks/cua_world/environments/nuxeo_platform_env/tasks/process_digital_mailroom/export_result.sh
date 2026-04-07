#!/bin/bash
# Export script for process_digital_mailroom
# Captures the state of Drop Box and target workspaces to a JSON file.

set -e
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Query Repository State
# We need to list children of: Drop Box, Contracts, Invoices, Assets

# Helper to list children of a path as JSON
get_children() {
    local path="$1"
    # Fetch children, include dc:title, dc:modified, and path
    curl -s -u "$NUXEO_AUTH" \
        -H "X-NXproperties: dublincore" \
        "$NUXEO_URL/api/v1/path$path/@children"
}

echo "Querying Drop Box..."
DROP_BOX_JSON=$(get_children "/default-domain/workspaces/Drop-Box")

echo "Querying Contracts..."
CONTRACTS_JSON=$(get_children "/default-domain/workspaces/Contracts")

echo "Querying Invoices..."
INVOICES_JSON=$(get_children "/default-domain/workspaces/Invoices")

echo "Querying Assets..."
ASSETS_JSON=$(get_children "/default-domain/workspaces/Assets")

# 3. Create Result JSON
# We combine these into a single JSON object for the python verifier
# We assume python3 is available.

export DROP_BOX_JSON
export CONTRACTS_JSON
export INVOICES_JSON
export ASSETS_JSON
export TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
export TASK_END_TIME=$(date +%s)

# Use python to assemble the final JSON safely
python3 -c '
import os
import json
import time

def safe_load(env_var):
    try:
        val = os.environ.get(env_var, "{}")
        return json.loads(val)
    except:
        return {"entries": []}

data = {
    "drop_box": safe_load("DROP_BOX_JSON"),
    "contracts": safe_load("CONTRACTS_JSON"),
    "invoices": safe_load("INVOICES_JSON"),
    "assets": safe_load("ASSETS_JSON"),
    "task_timing": {
        "start": int(os.environ.get("TASK_START_TIME", 0)),
        "end": int(os.environ.get("TASK_END_TIME", 0))
    },
    "screenshot_path": "/tmp/task_final.png"
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(data, f, indent=2)
'

# 4. Handle Permissions for Copy
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"