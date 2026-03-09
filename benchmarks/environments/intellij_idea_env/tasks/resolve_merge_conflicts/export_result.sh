#!/bin/bash
echo "=== Exporting resolve_merge_conflicts result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/commons-inventory"
cd "$PROJECT_DIR"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Capture Git State
GIT_STATUS=$(git status --porcelain)
GIT_LOG=$(git log --oneline -5)
IS_MERGE_IN_PROGRESS=false
if [ -f .git/MERGE_HEAD ]; then
    IS_MERGE_IN_PROGRESS=true
fi

# 2. Capture File Contents
read_file() {
    if [ -f "$1" ]; then
        cat "$1"
    else
        echo ""
    fi
}

POM_CONTENT=$(read_file "pom.xml")
PRODUCT_CONTENT=$(read_file "src/main/java/com/inventory/model/Product.java")
MANAGER_CONTENT=$(read_file "src/main/java/com/inventory/service/InventoryManager.java")
UTILS_CONTENT=$(read_file "src/main/java/com/inventory/util/InventoryUtils.java")

# 3. Check for Conflict Markers
HAS_CONFLICT_MARKERS=false
if grep -rE "<<<<<<<|=======|>>>>>>>" . > /dev/null 2>&1; then
    HAS_CONFLICT_MARKERS=true
fi

# 4. Attempt Compilation
COMPILE_SUCCESS=false
COMPILE_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn compile -B 2>&1 || true)
if echo "$COMPILE_OUTPUT" | grep -q "BUILD SUCCESS"; then
    COMPILE_SUCCESS=true
fi

# 5. Export to JSON using Python to handle escaping safely
python3 << EOF
import json
import os
import sys

def safe_read(path):
    if os.path.exists(path):
        with open(path, 'r', errors='replace') as f:
            return f.read()
    return ""

result = {
    "git_status_porcelain": """$GIT_STATUS""",
    "git_log": """$GIT_LOG""",
    "is_merge_in_progress": "$IS_MERGE_IN_PROGRESS" == "true",
    "has_conflict_markers": "$HAS_CONFLICT_MARKERS" == "true",
    "compile_success": "$COMPILE_SUCCESS" == "true",
    "pom_content": """$POM_CONTENT""",
    "product_content": """$PRODUCT_CONTENT""",
    "manager_content": """$MANAGER_CONTENT""",
    "utils_content": """$UTILS_CONTENT""",
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="