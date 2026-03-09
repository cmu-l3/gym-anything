#!/bin/bash
echo "=== Exporting batch_deploy_archive results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check for existence of artifacts in Artifactory via REST API
# We need to check if /example-repo-local/libs/commons-lang3.jar exists
# and /example-repo-local/libs/commons-io.jar exists

REPO="example-repo-local"
FILE1_PATH="libs/commons-lang3.jar"
FILE2_PATH="libs/commons-io.jar"

check_artifact() {
    local path="$1"
    # Use HEAD to get headers including checksums and size
    local response
    response=$(curl -s -I -u "${ADMIN_USER}:${ADMIN_PASS}" "${ARTIFACTORY_URL}/artifactory/${REPO}/${path}")
    
    local http_code
    http_code=$(echo "$response" | head -n 1 | cut -d$' ' -f2)
    
    if [ "$http_code" == "200" ]; then
        # Extract metadata
        local sha1
        sha1=$(echo "$response" | grep -i "X-Checksum-Sha1" | cut -d' ' -f2 | tr -d '\r')
        local size
        size=$(echo "$response" | grep -i "Content-Length" | cut -d' ' -f2 | tr -d '\r')
        local last_modified
        last_modified=$(echo "$response" | grep -i "Last-Modified" | cut -d':' -f2- | tr -d '\r')
        
        # We also want the creation time, but HEAD might not give creation time explicitly 
        # distinct from modification if uploaded fresh. 
        # We can use the detailed storage API for precise creation time.
        local api_json
        api_json=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" "${ARTIFACTORY_URL}/artifactory/api/storage/${REPO}/${path}")
        local created_str
        created_str=$(echo "$api_json" | python3 -c "import sys, json; print(json.load(sys.stdin).get('created', ''))" 2>/dev/null)
        
        # Convert created ISO8601 to epoch
        local created_epoch=0
        if [ -n "$created_str" ]; then
            created_epoch=$(date -d "$created_str" +%s 2>/dev/null || echo "0")
        fi

        echo "{\"exists\": true, \"sha1\": \"$sha1\", \"size\": $size, \"created\": $created_epoch}"
    else
        echo "{\"exists\": false}"
    fi
}

echo "Checking artifact: $FILE1_PATH"
RESULT1=$(check_artifact "$FILE1_PATH")
echo "Checking artifact: $FILE2_PATH"
RESULT2=$(check_artifact "$FILE2_PATH")

# Get expected checksums
EXP_SHA1_LANG=$(cat /tmp/expected_sha1_lang3.txt 2>/dev/null || echo "")
EXP_SHA1_IO=$(cat /tmp/expected_sha1_io.txt 2>/dev/null || echo "")

# 3. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "artifact_lang3": $RESULT1,
    "artifact_io": $RESULT2,
    "expected_sha1_lang3": "$EXP_SHA1_LANG",
    "expected_sha1_io": "$EXP_SHA1_IO"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="