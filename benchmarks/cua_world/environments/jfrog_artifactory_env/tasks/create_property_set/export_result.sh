#!/bin/bash
# Export script for create_property_set task
set -e

echo "=== Exporting create_property_set result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Capture final system configuration
# The GET /api/system/configuration endpoint returns the full descriptor XML
# containing Property Sets and Repository configurations.
echo "Fetching system configuration..."
curl -s -u admin:password "http://localhost:8082/artifactory/api/system/configuration" > /tmp/final_config.xml

# 3. Check timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
CONFIG_SIZE=$(stat -c %s /tmp/final_config.xml 2>/dev/null || echo "0")

# 4. Create result JSON
# We treat the XML config as the primary artifact.
# We also check if the file is valid XML (basic check).

VALID_XML="false"
if [ -s /tmp/final_config.xml ] && grep -q "<config" /tmp/final_config.xml; then
    VALID_XML="true"
fi

cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_xml_path": "/tmp/final_config.xml",
    "config_size": $CONFIG_SIZE,
    "valid_xml_captured": $VALID_XML,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move files to a location accessible by copy_from_env (tmp is fine, just ensure perms)
chmod 644 /tmp/task_result.json
chmod 644 /tmp/final_config.xml
chmod 644 /tmp/task_final.png

echo "Export complete. Result JSON:"
cat /tmp/task_result.json