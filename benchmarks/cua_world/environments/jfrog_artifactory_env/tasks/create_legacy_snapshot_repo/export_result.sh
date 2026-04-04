#!/bin/bash
# Export script for create_legacy_snapshot_repo task
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Query Repository Configuration
# We need to verify specific internal settings (snapshotVersionBehavior)
# which might require the specific repo endpoint.
REPO_KEY="legacy-dev-local"
API_URL="http://localhost:8082/artifactory/api/repositories/${REPO_KEY}"

echo "Querying repository configuration for ${REPO_KEY}..."
http_code=$(curl -s -o /tmp/repo_config.json -w "%{http_code}" -u admin:password "${API_URL}")

echo "HTTP Code: $http_code"

# If the specific endpoint fails (OSS restriction), fallback to system configuration
# The system configuration XML contains all repo details.
USED_FALLBACK="false"
if [ "$http_code" != "200" ]; then
    echo "Direct repo query failed (likely OSS restriction). Trying System Configuration..."
    # Fetch system config (XML)
    curl -s -u admin:password "http://localhost:8082/artifactory/api/system/configuration" > /tmp/system_config.xml
    
    # Simple grep/parsing to extract the specific repo block is risky with XML.
    # We will let the python verifier handle the XML parsing if needed, 
    # or try to convert relevant parts to JSON here.
    # For now, we'll mark that we have the config.
    USED_FALLBACK="true"
    
    # Attempt to extract just the relevant section for the JSON result if possible, 
    # but full XML parsing is better done in Python if verifier supports it.
    # To keep the JSON simple, we will set repo_exists=false here if we can't confirm it yet,
    # and let python do the heavy lifting.
fi

# 3. Get Task Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 4. Prepare JSON Result
# We construct a JSON object. If we have the direct JSON response, we embed it.
# If we used fallback, we might just pass the raw XML content or a flag.
# For simplicity, we'll read the JSON file content into a variable if it exists.

REPO_CONFIG_CONTENT="{}"
if [ -f /tmp/repo_config.json ] && [ "$http_code" == "200" ]; then
    REPO_CONFIG_CONTENT=$(cat /tmp/repo_config.json)
fi

# Create export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "http_status": "$http_code",
    "used_fallback": $USED_FALLBACK,
    "repo_config": $REPO_CONFIG_CONTENT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

# If we used fallback XML, make sure it's accessible to the verifier
if [ "$USED_FALLBACK" == "true" ]; then
    chmod 666 /tmp/system_config.xml 2>/dev/null || true
fi

echo "Export complete. Result saved to /tmp/task_result.json"