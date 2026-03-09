#!/bin/bash
set -e
echo "=== Exporting create_repo_layout results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM verification
take_screenshot /tmp/task_final.png

# Fetch the full system configuration to verify the layout
# We use the system configuration endpoint because it provides a reliable XML dump of all layouts
echo "Fetching system configuration..."
curl -s -u admin:password "http://localhost:8082/artifactory/api/system/configuration" > /tmp/system_config.xml

# Check if curl failed
if [ ! -s /tmp/system_config.xml ]; then
    echo "ERROR: Failed to retrieve system configuration or file is empty."
    CONFIG_RETRIEVED="false"
else
    CONFIG_RETRIEVED="true"
fi

# Create a JSON result wrapper
# We will embed the relevant XML snippet or just point to the file, 
# but for the verifier, it's safer to have the file available via copy_from_env.
# We'll create a simple JSON metadata file.

cat > /tmp/task_result.json << EOF
{
    "timestamp": "$(date -Iseconds)",
    "config_retrieved": $CONFIG_RETRIEVED,
    "system_config_path": "/tmp/system_config.xml",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 644 /tmp/task_result.json
chmod 644 /tmp/system_config.xml 2>/dev/null || true
chmod 644 /tmp/task_final.png 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"