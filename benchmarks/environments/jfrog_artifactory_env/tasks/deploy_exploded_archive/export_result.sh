#!/bin/bash
echo "=== Exporting deploy_exploded_archive result ==="

source /workspace/scripts/task_utils.sh

# Task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if Artifactory is accessible
API_ACCESSIBLE="false"
if wait_for_artifactory 10; then
    API_ACCESSIBLE="true"
fi

# ============================================================
# Verification Logic
# ============================================================

REPO="example-repo-local"
BASE_PATH="javadocs/commons-lang3"

# Helper to check file existence via API
check_file_exists() {
    local path="$1"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" -u "${ADMIN_USER}:${ADMIN_PASS}" \
        "${ARTIFACTORY_URL}/artifactory/api/storage/${REPO}/${path}")
    if [ "$code" == "200" ]; then
        echo "true"
    else
        echo "false"
    fi
}

# Check for critical exploded files
INDEX_EXISTS=$(check_file_exists "${BASE_PATH}/index.html")
ELEMENT_LIST_EXISTS=$(check_file_exists "${BASE_PATH}/element-list")
HELP_DOC_EXISTS=$(check_file_exists "${BASE_PATH}/help-doc.html")

# Check if the unexploded JAR exists at the target path (common mistake)
# If the user uploaded to javadocs/commons-lang3 but didn't explode,
# the file might be named 'commons-lang3-javadoc.jar' inside that folder
# or they might have uploaded it AS 'commons-lang3' (file).
JAR_EXISTS_AT_PATH=$(check_file_exists "${BASE_PATH}/commons-lang3-javadoc.jar")
IS_FILE_NOT_FOLDER="false"
# Check if the path itself is a file instead of a folder (by checking storage info)
PATH_TYPE=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${ARTIFACTORY_URL}/artifactory/api/storage/${REPO}/${BASE_PATH}" | \
    python3 -c "import sys, json; print(json.load(sys.stdin).get('mimeType', ''))" 2>/dev/null)

if [ "$PATH_TYPE" == "application/java-archive" ]; then
    IS_FILE_NOT_FOLDER="true"
fi

# Get creation time of index.html if it exists (to verify it was created during task)
CREATION_TIME_MATCH="false"
if [ "$INDEX_EXISTS" == "true" ]; then
    # Get created ISO timestamp
    CREATED_ISO=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
        "${ARTIFACTORY_URL}/artifactory/api/storage/${REPO}/${BASE_PATH}/index.html" | \
        python3 -c "import sys, json; print(json.load(sys.stdin).get('created', ''))")
    
    # Convert ISO to unix (simple python conversion)
    CREATED_UNIX=$(python3 -c "import dateutil.parser; print(int(dateutil.parser.isoparse('${CREATED_ISO}').timestamp()))" 2>/dev/null || echo "0")
    
    if [ "$CREATED_UNIX" -gt "$TASK_START" ]; then
        CREATION_TIME_MATCH="true"
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "api_accessible": $API_ACCESSIBLE,
    "index_html_exists": $INDEX_EXISTS,
    "element_list_exists": $ELEMENT_LIST_EXISTS,
    "help_doc_exists": $HELP_DOC_EXISTS,
    "jar_exists_unexploded": $JAR_EXISTS_AT_PATH,
    "target_is_file_not_folder": $IS_FILE_NOT_FOLDER,
    "creation_time_valid": $CREATION_TIME_MATCH,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="