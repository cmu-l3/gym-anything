#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
ga_x "scrot /tmp/task_final.png" 2>/dev/null || true

# 2. Record task timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Query Nuxeo API to get the state of the 'Clients' workspace children
# We use enriched headers to get tags and dublincore properties
echo "Querying Nuxeo API for final state..."

# Fetch children of the Clients workspace
# Note: NXQL query to find everything inside the Clients path
API_RESPONSE=$(curl -s -u "$NUXEO_AUTH" \
    -H "X-NXenrichers.document: tags" \
    -H "X-NXproperties: dublincore" \
    "$NUXEO_URL/api/v1/search/lang/NXQL/execute?query=SELECT+*+FROM+Document+WHERE+ecm:parentId+=+(SELECT+ecm:uuid+FROM+Document+WHERE+ecm:path='/default-domain/workspaces/Clients')+AND+ecm:isTrashed=0")

# Save API response to a file for the verifier to parse
echo "$API_RESPONSE" > /tmp/nuxeo_children.json

# 4. Create main result JSON
# We'll rely on the python verifier to parse the complex API JSON, 
# so we just export high-level metadata here.
cat > /tmp/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png",
    "api_dump_path": "/tmp/nuxeo_children.json"
}
EOF

# Ensure permissions allow extraction
chmod 644 /tmp/task_result.json
chmod 644 /tmp/nuxeo_children.json
chmod 644 /tmp/task_final.png 2>/dev/null || true

echo "Export complete. State saved to /tmp/task_result.json and /tmp/nuxeo_children.json"