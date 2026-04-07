#!/bin/bash
# Setup for create_section_hierarchy task
# Ensures Nuxeo is running, cleans any prior section hierarchy, and opens browser.

source /workspace/scripts/task_utils.sh

echo "=== Setting up create_section_hierarchy task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Wait for Nuxeo to be available
wait_for_nuxeo 180

# ---------------------------------------------------------------------------
# Clean up: Remove any pre-existing "Department Publications" section
# ---------------------------------------------------------------------------
echo "Cleaning up any pre-existing sections..."

# Try to delete the parent directly (recursive delete)
PARENT_PATH="/default-domain/sections/Department-Publications"
if doc_exists "$PARENT_PATH"; then
    echo "  Removing existing parent: $PARENT_PATH"
    nuxeo_api DELETE "/path$PARENT_PATH" > /dev/null 2>&1 || true
    sleep 2
fi

# Ensure trash is purged of these items to prevent confusion
echo "  Purging trash..."
nuxeo_api POST "/search/pp/advanced_document_content/execute" \
    '{"params":{"queryParams":["SELECT * FROM Section WHERE ecm:isTrashed = 1 AND dc:title IN ('\''Department Publications'\'', '\''Engineering'\'', '\''Marketing'\'', '\''Legal'\'')"]},"context":{}}' \
    | python3 -c "import sys,json; ids=[d.get('uid') for d in json.load(sys.stdin).get('entries',[])]; print('\n'.join(ids))" \
    | while read -r uid; do
        if [ -n "$uid" ]; then
            nuxeo_api DELETE "/id/$uid" > /dev/null 2>&1 || true
        fi
    done

# Verify sections root exists (it should by default)
if ! doc_exists "/default-domain/sections"; then
    echo "WARNING: /default-domain/sections does not exist — Nuxeo may not be fully initialized."
fi

# Record initial section count for anti-gaming
INITIAL_COUNT=$(nuxeo_api GET "/path/default-domain/sections/@children" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('resultsCount', 0))" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_section_count.txt
echo "Initial child section count under /default-domain/sections: $INITIAL_COUNT"

# ---------------------------------------------------------------------------
# Open Firefox to Nuxeo Web UI home
# ---------------------------------------------------------------------------
# We navigate to the home page, not the Sections page, to force the agent
# to demonstrate they know how to navigate to Sections.
open_nuxeo_url "$NUXEO_UI" 10
nuxeo_login

# Ensure we are on the dashboard/home
navigate_to "$NUXEO_UI"
sleep 3

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="