#!/bin/bash
echo "=== Exporting Configure Global Scripts Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Fetch current global scripts from API
echo "Fetching current global scripts..."
CURRENT_SCRIPTS_XML=$(curl -sk -X GET -u admin:admin \
    -H "X-Requested-With: OpenAPI" \
    -H "Accept: application/xml" \
    "https://localhost:8443/api/server/globalScripts" 2>/dev/null)

# Save to temp file for processing
echo "$CURRENT_SCRIPTS_XML" > /tmp/current_global_scripts.xml

# 2. Parse XML to JSON using Python
# The XML structure is a Map with 4 entries. We want to extract the code strings.
python3 -c "
import xml.etree.ElementTree as ET
import json
import sys

xml_content = sys.stdin.read()
result = {'Deploy': '', 'Undeploy': '', 'Preprocessor': '', 'Postprocessor': ''}

try:
    if xml_content.strip():
        root = ET.fromstring(xml_content)
        # Iterate over entries in the map
        for entry in root.findall('entry'):
            strings = entry.findall('string')
            if len(strings) >= 2:
                key = strings[0].text
                value = strings[1].text if strings[1].text else ''
                if key in result:
                    result[key] = value
except Exception as e:
    result['error'] = str(e)

print(json.dumps(result))
" < /tmp/current_global_scripts.xml > /tmp/parsed_scripts.json

# 3. Check for modification (Anti-gaming)
INITIAL_HASH=$(cat /tmp/initial_scripts_hash.txt 2>/dev/null || echo "none")
CURRENT_HASH=$(md5sum /tmp/current_global_scripts.xml 2>/dev/null | awk '{print $1}')

SCRIPTS_MODIFIED="false"
if [ "$INITIAL_HASH" != "$CURRENT_HASH" ]; then
    SCRIPTS_MODIFIED="true"
fi

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create final result JSON
# We embed the parsed scripts directly into the result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "scripts_modified": $SCRIPTS_MODIFIED,
    "scripts_content": $(cat /tmp/parsed_scripts.json),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="