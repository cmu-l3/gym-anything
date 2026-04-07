#!/bin/bash
# Export script for Configure Data Retention task

echo "=== Exporting Configure Data Retention Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png
echo "Final screenshot saved"

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Query current PrivacyManager settings from database
echo "Querying current privacy settings..."
SETTINGS_DATA=$(matomo_query "SELECT option_name, option_value FROM matomo_option WHERE option_name LIKE 'PrivacyManager.%'" 2>/dev/null)

# Parse settings into a JSON-friendly format (associative array concept in bash)
# We will use python to reliably construct the JSON from the raw SQL output
# The output format of matomo_query (mysql -N) is tab-separated: key\tvalue

# Python script to parse SQL output and create JSON
python3 -c "
import sys
import json
import time

def parse_settings(raw_data):
    settings = {}
    if not raw_data:
        return settings
    
    for line in raw_data.strip().split('\n'):
        parts = line.split('\t')
        if len(parts) >= 2:
            key = parts[0].strip()
            # Remove prefix for cleaner JSON
            short_key = key.replace('PrivacyManager.', '')
            value = parts[1].strip()
            settings[short_key] = value
    return settings

# Read raw data passed as argument
raw_data = '''$SETTINGS_DATA'''

current_settings = parse_settings(raw_data)

# Read initial settings to detect changes
initial_settings = {}
try:
    with open('/tmp/initial_privacy_options.txt', 'r') as f:
        initial_raw = f.read()
        initial_settings = parse_settings(initial_raw)
except:
    pass

# Check which keys changed
changed_keys = []
for key, val in current_settings.items():
    if key not in initial_settings or initial_settings[key] != val:
        changed_keys.append(key)

result = {
    'task_start_timestamp': $TASK_START,
    'task_end_timestamp': $TASK_END,
    'settings': current_settings,
    'initial_settings': initial_settings,
    'changed_keys': changed_keys,
    'settings_found': len(current_settings) > 0,
    'screenshot_path': '/tmp/task_final_screenshot.png',
    'export_timestamp': time.strftime('%Y-%m-%dT%H:%M:%S')
}

print(json.dumps(result, indent=4))
" > /tmp/configure_data_retention_result.json

# Safe copy to output
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/configure_data_retention_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="