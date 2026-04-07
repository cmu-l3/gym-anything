#!/bin/bash
# post_task hook for create_project_readme task.
# Exports the created note's content and the UIDs of target documents for verification.

echo "=== Exporting create_project_readme results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# We need to find the note created by the agent.
# It might be named "Project-Readme", "Project-Read-Me", etc.
# We'll search by title "Project Readme" or path.

PROJECTS_PATH="/default-domain/workspaces/Projects"

# 1. Get UIDs of the target documents (the ones that should be linked)
# These act as the ground truth for link verification.
echo "Fetching target document UIDs..."
UID_REPORT=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path$PROJECTS_PATH/Annual-Report-2023" | python3 -c "import sys, json; print(json.load(sys.stdin).get('uid', ''))" 2>/dev/null)
UID_PROPOSAL=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path$PROJECTS_PATH/Project-Proposal" | python3 -c "import sys, json; print(json.load(sys.stdin).get('uid', ''))" 2>/dev/null)

echo "Target UIDs: Report=$UID_REPORT, Proposal=$UID_PROPOSAL"

# 2. Find the agent's Note document
# Try by path first
NOTE_JSON=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path$PROJECTS_PATH/Project-Readme")
NOTE_UID=$(echo "$NOTE_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('uid', ''))" 2>/dev/null)

if [ -z "$NOTE_UID" ]; then
    # Try searching by title if path lookup failed
    echo "Note not found by path 'Project-Readme', searching by title..."
    SEARCH_RES=$(curl -s -u "$NUXEO_AUTH" \
        "$NUXEO_URL/api/v1/search/lang/NXQL/execute?query=SELECT+*+FROM+Note+WHERE+ecm:path+STARTSWITH+'$PROJECTS_PATH'+AND+dc:title='Project+Readme'+AND+ecm:isTrashed=0+ORDER+BY+dc:created+DESC")
    
    # Get the most recent one
    NOTE_JSON=$(echo "$SEARCH_RES" | python3 -c "import sys, json; entries=json.load(sys.stdin).get('entries', []); print(json.dumps(entries[0])) if entries else print('')" 2>/dev/null)
    NOTE_UID=$(echo "$NOTE_JSON" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('uid', '')) if d else print('')" 2>/dev/null)
fi

# 3. Extract Note Content
NOTE_CONTENT=""
NOTE_TITLE=""
NOTE_EXISTS="false"

if [ -n "$NOTE_UID" ]; then
    NOTE_EXISTS="true"
    NOTE_TITLE=$(echo "$NOTE_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('properties', {}).get('dc:title', ''))" 2>/dev/null)
    # Get the HTML content from note:note property
    NOTE_CONTENT=$(echo "$NOTE_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('properties', {}).get('note:note', ''))" 2>/dev/null)
    echo "Found Note: '$NOTE_TITLE' ($NOTE_UID)"
else
    echo "Note document not found."
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "note_exists": $NOTE_EXISTS,
    "note_uid": "$NOTE_UID",
    "note_title": "$(echo "$NOTE_TITLE" | sed 's/"/\\"/g')",
    "note_content": "$(echo "$NOTE_CONTENT" | sed 's/"/\\"/g' | tr -d '\n')",
    "target_uids": {
        "annual_report": "$UID_REPORT",
        "project_proposal": "$UID_PROPOSAL"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="