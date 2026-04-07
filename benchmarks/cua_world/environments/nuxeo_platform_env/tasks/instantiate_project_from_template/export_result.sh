#!/bin/bash
# post_task hook for instantiate_project_from_template
# Exports the state of the 'Project Phoenix' workspace and the original template

echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Define paths
TARGET_PATH="/default-domain/workspaces/Projects/Project-Phoenix"
TEMPLATE_PATH="/default-domain/workspaces/Templates/Standard-Project-Template"

# 1. Get Target Workspace Details
echo "Fetching target workspace details..."
TARGET_JSON=$(nuxeo_api GET "/path$TARGET_PATH" "?enrichers.document=children")

# 2. Get Source Template Details (to verify it wasn't moved/deleted)
echo "Fetching source template details..."
SOURCE_JSON=$(nuxeo_api GET "/path$TEMPLATE_PATH")

# 3. Get Children of Target (Deep verification of structure)
# The enricher above gives us immediate children, but let's be explicit
CHILDREN_JSON=$(nuxeo_api GET "/path$TARGET_PATH/@children")

# 4. Check for 'Copy of' artifacts (partial success check)
# Sometimes agents paste but forget to rename. We search for "Standard-Project-Template" in Projects.
ARTIFACTS_JSON=$(nuxeo_api GET "/path/default-domain/workspaces/Projects/@children")

# Construct the result JSON
# Use Python to safely assemble the JSON to avoid quoting hell in bash
python3 -c "
import json
import sys
import os

try:
    target = json.loads('''$TARGET_JSON''')
except:
    target = {}

try:
    source = json.loads('''$SOURCE_JSON''')
except:
    source = {}

try:
    children = json.loads('''$CHILDREN_JSON''')
except:
    children = {}
    
try:
    artifacts = json.loads('''$ARTIFACTS_JSON''')
except:
    artifacts = {}

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'target_exists': target.get('entity-type') == 'document',
    'target_title': target.get('title', ''),
    'target_path': target.get('path', ''),
    'target_uid': target.get('uid', ''),
    'target_created': target.get('properties', {}).get('dc:created', ''),
    'source_exists': source.get('entity-type') == 'document',
    'source_uid': source.get('uid', ''),
    'children_names': [e.get('name') for e in children.get('entries', [])],
    'children_titles': [e.get('title') for e in children.get('entries', [])],
    'project_contents': [e.get('title') for e in artifacts.get('entries', [])]
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json