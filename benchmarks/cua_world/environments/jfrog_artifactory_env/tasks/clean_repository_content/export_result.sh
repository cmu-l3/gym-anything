#!/bin/bash
echo "=== Exporting Clean Repository Content Result ==="

source /workspace/scripts/task_utils.sh

REPO_KEY="example-repo-local"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# ============================================================
# 1. Check if Repository Still Exists (CRITICAL)
# ============================================================
echo "Checking if repository exists..."
# Using repo_exists utility which parses the list
REPO_EXISTS="false"
if repo_exists "$REPO_KEY"; then
    REPO_EXISTS="true"
    echo "Repository $REPO_KEY still exists (Good)."
else
    echo "Repository $REPO_KEY was deleted (Bad)."
fi

# ============================================================
# 2. Check Repository Content (Should be Empty)
# ============================================================
echo "Checking repository content..."
# Use Storage API with deep list
# If repo is deleted, this returns error, handled by '|| echo 0'
# If repo is empty, 'files' array is empty or path doesn't exist
STORAGE_JSON=$(curl -s -u admin:password "${ARTIFACTORY_URL}/artifactory/api/storage/${REPO_KEY}?list&deep=1" 2>/dev/null)

# Count files (items that are not folders)
FILE_COUNT=$(echo "$STORAGE_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # If files list exists, count items that aren't folders (folders might remain or not depending on delete method)
    # However, 'Zap' or recursive delete usually removes everything.
    files = data.get('files', [])
    print(len(files))
except:
    print('0') # If 404 or empty, count is 0
")

echo "Final file count: $FILE_COUNT"

# Specific check for the artifacts we seeded
ARTIFACT_1_GONE="false"
STATUS_1=$(curl -s -o /dev/null -w "%{http_code}" -u admin:password "${ARTIFACTORY_URL}/artifactory/${REPO_KEY}/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar")
if [ "$STATUS_1" = "404" ]; then ARTIFACT_1_GONE="true"; fi

ARTIFACT_2_GONE="false"
STATUS_2=$(curl -s -o /dev/null -w "%{http_code}" -u admin:password "${ARTIFACTORY_URL}/artifactory/${REPO_KEY}/commons-io/commons-io/2.15.1/commons-io-2.15.1.jar")
if [ "$STATUS_2" = "404" ]; then ARTIFACT_2_GONE="true"; fi

echo "Artifact 1 Gone: $ARTIFACT_1_GONE"
echo "Artifact 2 Gone: $ARTIFACT_2_GONE"

# ============================================================
# 3. Create Result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "repo_exists": $REPO_EXISTS,
    "final_file_count": $FILE_COUNT,
    "artifact_1_gone": $ARTIFACT_1_GONE,
    "artifact_2_gone": $ARTIFACT_2_GONE,
    "task_timestamp": $TASK_START,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="