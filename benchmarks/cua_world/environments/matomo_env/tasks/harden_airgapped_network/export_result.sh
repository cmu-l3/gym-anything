#!/bin/bash
# Export script for Harden Air-gapped Network task

echo "=== Exporting Configuration Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Get task start time
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Path to config inside container
CONFIG_PATH="/var/www/html/config/config.ini.php"

# Check if file exists
FILE_EXISTS="false"
if docker exec matomo-app test -f "$CONFIG_PATH"; then
    FILE_EXISTS="true"
fi

# Get file modification time
FILE_MTIME="0"
if [ "$FILE_EXISTS" = "true" ]; then
    FILE_MTIME=$(docker exec matomo-app stat -c %Y "$CONFIG_PATH" 2>/dev/null || echo "0")
fi

# Check if file was modified during task
MODIFIED_DURING_TASK="false"
if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    MODIFIED_DURING_TASK="true"
fi

# Extract the content of the config file
# We use base64 to safely transport it out of the container without character encoding issues
CONFIG_CONTENT_B64=""
if [ "$FILE_EXISTS" = "true" ]; then
    CONFIG_CONTENT_B64=$(docker exec matomo-app base64 -w 0 "$CONFIG_PATH" 2>/dev/null)
fi

# Parse the config content using Python to extract specific keys
# We look for the keys in the [General] section
PARSED_VALUES=$(python3 -c "
import sys
import base64
import configparser
import io

try:
    content_b64 = '$CONFIG_CONTENT_B64'
    if not content_b64:
        print('{}')
        sys.exit(0)
        
    content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
    
    # Matomo config often starts with '; <?php exit; ?>' which configparser might handle as a comment
    # But just in case, let's create a custom parser or just grep line by line for robustness against PHP headers
    
    # Simple line-based parser to avoid strict INI parsing issues with PHP code
    settings = {}
    current_section = None
    
    for line in content.splitlines():
        line = line.strip()
        if line.startswith('[') and line.endswith(']'):
            current_section = line[1:-1]
        elif '=' in line and not line.startswith(';'):
            key, val = line.split('=', 1)
            key = key.strip()
            val = val.strip().strip('\"').strip('\'')
            if current_section == 'General':
                settings[key] = val
                
    import json
    print(json.dumps(settings))

except Exception as e:
    print(json.dumps({'error': str(e)}))
")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/harden_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_mtime": $FILE_MTIME,
    "modified_during_task": $MODIFIED_DURING_TASK,
    "config_values": $PARSED_VALUES,
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

# Save result with permissions
rm -f /tmp/harden_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/harden_result.json
chmod 666 /tmp/harden_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/harden_result.json"
cat /tmp/harden_result.json
echo ""
echo "=== Export Complete ==="