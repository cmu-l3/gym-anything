#!/bin/bash
echo "=== Exporting configure_virtual_deploy_target result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Get the final configuration of the virtual repository
echo "Fetching repository configuration..."
REPO_CONFIG=$(get_repo_info "libs-virtual")

# Check if Artifactory is accessible
API_STATUS="unknown"
if [ -n "$REPO_CONFIG" ]; then
    API_STATUS="accessible"
else
    API_STATUS="unreachable"
fi

# Prepare JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0"),
    "export_time": $(date +%s),
    "api_status": "$API_STATUS",
    "repo_config": $REPO_CONFIG,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissive permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="