#!/bin/bash
# Export script for configure_tax_type task
# Extracts the created tax configuration using Drush and saves it to JSON

echo "=== Exporting Configure Tax Type Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Go to Drupal directory
cd /var/www/html/drupal
DRUSH="vendor/bin/drush"

# 1. Get current tax configurations
$DRUSH config:list --prefix="commerce_tax.commerce_tax_type" --format=json > /tmp/current_tax_configs.json 2>/dev/null || echo "[]" > /tmp/current_tax_configs.json

# 2. Identify the NEW tax configuration
# We use python to diff the JSON lists and find the new entry
NEW_CONFIG_NAME=$(python3 -c "
import json
try:
    with open('/tmp/initial_tax_configs.json') as f:
        initial = set(json.load(f))
    with open('/tmp/current_tax_configs.json') as f:
        current = set(json.load(f))
    
    new_configs = list(current - initial)
    
    # If multiple new ones, prefer one with 'california' in name, else take last
    selected = ''
    if new_configs:
        selected = new_configs[0]
        for cfg in new_configs:
            if 'california' in cfg.lower():
                selected = cfg
                break
    print(selected)
except Exception:
    print('')
")

echo "Identified new tax config: '$NEW_CONFIG_NAME'"

# 3. Export the full configuration details for the new tax type
CONFIG_JSON="{}"
if [ -n "$NEW_CONFIG_NAME" ]; then
    echo "Exporting configuration for $NEW_CONFIG_NAME..."
    # Drush config:get outputs YAML by default, --format=json gives us a nice JSON object
    CONFIG_JSON=$($DRUSH config:get "$NEW_CONFIG_NAME" --format=json 2>/dev/null)
    
    # If drush failed to output valid JSON, fallback to empty object
    if [ -z "$CONFIG_JSON" ] || [ "$CONFIG_JSON" == "null" ]; then
        CONFIG_JSON="{}"
    fi
fi

# 4. Check if UI shows the tax type (backup verification via DB/cache)
# Sometimes config is saved but cache not cleared
$DRUSH cr > /dev/null 2>&1

# 5. Create the result JSON file
# We embed the entire exported configuration JSON into our result
TEMP_JSON=$(mktemp /tmp/tax_result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "new_config_name": "$NEW_CONFIG_NAME",
    "config_data": $CONFIG_JSON,
    "task_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
echo "=== Export Complete ==="