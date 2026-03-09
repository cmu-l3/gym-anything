#!/bin/bash
echo "=== Exporting git_init_and_commit result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/commons-cli"

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Gather Evidence

# Check if .git exists
GIT_EXISTS="false"
GIT_DIR_TIMESTAMP="0"
if [ -d "$PROJECT_DIR/.git" ]; then
    GIT_EXISTS="true"
    GIT_DIR_TIMESTAMP=$(stat -c %Y "$PROJECT_DIR/.git" 2>/dev/null || echo "0")
fi

# Check .gitignore
GITIGNORE_EXISTS="false"
GITIGNORE_CONTENT=""
if [ -f "$PROJECT_DIR/.gitignore" ]; then
    GITIGNORE_EXISTS="true"
    GITIGNORE_CONTENT=$(cat "$PROJECT_DIR/.gitignore")
fi

# Run Git commands to inspect repository state
COMMIT_MSG=""
COMMIT_COUNT="0"
TRACKED_FILES=""
IGNORED_FILES_CHECK=""

if [ "$GIT_EXISTS" = "true" ]; then
    cd "$PROJECT_DIR"

    # Get last commit message
    COMMIT_MSG=$(git log -1 --pretty=%B 2>/dev/null || echo "")
    
    # Get commit count
    COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo "0")
    
    # List tracked files (to verify source files are in and target files are out)
    TRACKED_FILES=$(git ls-tree -r HEAD --name-only 2>/dev/null || echo "")
    
    # Check if 'target' is ignored
    if git check-ignore -q target/FakeClass.class 2>/dev/null; then
        IGNORED_FILES_CHECK="target_ignored"
    else
        IGNORED_FILES_CHECK="target_not_ignored"
    fi
fi

# Check Eclipse UI state (looking for EGit views)
ECLIPSE_VIEWS=$(DISPLAY=:1 wmctrl -l | grep "Eclipse" || echo "")
IS_STAGING_VIEW_OPEN="false"
# Note: wmctrl usually only sees the main window title, identifying specific views 
# inside Eclipse via shell is hard, so we rely on VLM for that part.

# 3. Create JSON payload
# Use python for safe JSON encoding
python3 << EOF
import json
import os
import time

def safe_read(path):
    try:
        with open(path, 'r', errors='replace') as f:
            return f.read()
    except:
        return ""

result = {
    "git_exists": ${GIT_EXISTS},
    "git_dir_timestamp": ${GIT_DIR_TIMESTAMP},
    "gitignore_exists": ${GITIGNORE_EXISTS},
    "gitignore_content": """${GITIGNORE_CONTENT}""",
    "commit_message": """${COMMIT_MSG}""",
    "commit_count": int("${COMMIT_COUNT}"),
    "tracked_files_sample": """$(echo "$TRACKED_FILES" | head -n 20)""",
    "has_tracked_java_files": ".java" in """${TRACKED_FILES}""",
    "has_tracked_target_files": "target/" in """${TRACKED_FILES}""",
    "ignored_check": "${IGNORED_FILES_CHECK}",
    "timestamp": int(time.time())
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="