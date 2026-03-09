#!/bin/bash
echo "=== Exporting Configure Snapshot Retention Result ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# 1. Get Global Configuration Descriptor
# This XML contains detailed settings for all repositories, including retention policies
# which are often not exposed in the simple REST API JSON list.
echo "Fetching system configuration..."
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${ARTIFACTORY_URL}/artifactory/api/system/configuration" \
    -o /tmp/artifactory_config.xml

# 2. Get Repository List (for basic existence check)
echo "Fetching repository list..."
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${ARTIFACTORY_URL}/artifactory/api/repositories" \
    -o /tmp/repo_list.json

# 3. Check if app is running
APP_RUNNING=$(pgrep -f "java" > /dev/null && echo "true" || echo "false")

# 4. Prepare result JSON
# We will do the heavy XML parsing in the Python verifier, 
# but we'll do a quick grep check here for debugging output.
CONFIG_CONTAINS_REPO=$(grep -c "project-alpha-snapshots" /tmp/artifactory_config.xml || echo "0")
CONFIG_CONTAINS_LIMIT=$(grep -c "maxUniqueSnapshots>5<" /tmp/artifactory_config.xml || echo "0")

cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "config_xml_path": "/tmp/artifactory_config.xml",
    "repo_list_path": "/tmp/repo_list.json",
    "screenshot_path": "/tmp/task_final.png",
    "debug_grep_repo": $CONFIG_CONTAINS_REPO,
    "debug_grep_limit": $CONFIG_CONTAINS_LIMIT,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json /tmp/artifactory_config.xml /tmp/repo_list.json /tmp/task_final.png 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"