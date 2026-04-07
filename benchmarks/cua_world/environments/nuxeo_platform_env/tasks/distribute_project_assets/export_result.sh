#!/bin/bash
# Export script for distribute_project_assets
# Checks the final location and UUIDs of the documents.

echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Load initial state
if [ -f /tmp/initial_state.json ]; then
    ORIG_REPORT_UID=$(jq -r .report_uid /tmp/initial_state.json)
    ORIG_ASSETS_UID=$(jq -r .assets_uid /tmp/initial_state.json)
else
    echo "ERROR: Initial state not found!"
    ORIG_REPORT_UID=""
    ORIG_ASSETS_UID=""
fi

# Paths
SOURCE_BASE="/default-domain/workspaces/Active-Projects/Project-Omega"
ARCHIVE_BASE="/default-domain/workspaces/Archives/2023"
LIBRARY_BASE="/default-domain/workspaces/Templates/Library"

# 1. Check Project Closure Report
# Expected: NOT in Source, IS in Archive. UUID in Archive == ORIG_REPORT_UID

# Check Source
REPORT_IN_SOURCE=$(nuxeo_api GET "/path$SOURCE_BASE/Project-Closure-Report")
REPORT_IN_SOURCE_CODE=$(echo "$REPORT_IN_SOURCE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('entity-type','error') == 'document' and '200' or '404')" 2>/dev/null || echo "404")

# Check Archive
REPORT_IN_ARCHIVE=$(nuxeo_api GET "/path$ARCHIVE_BASE/Project-Closure-Report")
REPORT_IN_ARCHIVE_UID=$(echo "$REPORT_IN_ARCHIVE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null)

# 2. Check Reusable Assets
# Expected: IS in Source, IS in Library. UUID in Library != ORIG_ASSETS_UID (Must be a copy)

# Check Source
ASSETS_IN_SOURCE=$(nuxeo_api GET "/path$SOURCE_BASE/Reusable-Assets")
ASSETS_IN_SOURCE_UID=$(echo "$ASSETS_IN_SOURCE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null)

# Check Library
ASSETS_IN_LIBRARY=$(nuxeo_api GET "/path$LIBRARY_BASE/Reusable-Assets")
ASSETS_IN_LIBRARY_UID=$(echo "$ASSETS_IN_LIBRARY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null)
ASSETS_IN_LIBRARY_CREATED=$(echo "$ASSETS_IN_LIBRARY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('properties',{}).get('dc:created',''))" 2>/dev/null)

# 3. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. JSON Export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" <<EOF
{
    "initial": {
        "report_uid": "$ORIG_REPORT_UID",
        "assets_uid": "$ORIG_ASSETS_UID"
    },
    "final": {
        "report_in_source_exists": $( [ "$REPORT_IN_SOURCE_CODE" == "200" ] && echo "true" || echo "false" ),
        "report_in_archive_uid": "$REPORT_IN_ARCHIVE_UID",
        "assets_in_source_uid": "$ASSETS_IN_SOURCE_UID",
        "assets_in_library_uid": "$ASSETS_IN_LIBRARY_UID",
        "assets_in_library_created": "$ASSETS_IN_LIBRARY_CREATED"
    },
    "task_end_timestamp": "$(date +%s)"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="