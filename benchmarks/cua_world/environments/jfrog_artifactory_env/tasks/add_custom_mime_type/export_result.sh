#!/bin/bash
echo "=== Exporting add_custom_mime_type results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MIME_EXISTS=$(cat /tmp/initial_mime_exists.txt 2>/dev/null || echo "false")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Export System Configuration
# This contains the MIME types table
echo "Exporting system configuration..."
curl -s -u admin:password "http://localhost:8082/artifactory/api/system/configuration" > /tmp/final_config.xml

# Check if config export was empty
CONFIG_SIZE=$(stat -c %s /tmp/final_config.xml 2>/dev/null || echo "0")

# Check if Artifactory is still running
APP_RUNNING=$(pgrep -f "java" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_mime_exists": $INITIAL_MIME_EXISTS,
    "config_export_size": $CONFIG_SIZE,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move files to accessible location for copy_from_env
# We need both the JSON and the XML
mv /tmp/final_config.xml /tmp/task_config_export.xml 2>/dev/null || true
chmod 666 /tmp/task_config_export.xml 2>/dev/null || true

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result and Config XML saved."