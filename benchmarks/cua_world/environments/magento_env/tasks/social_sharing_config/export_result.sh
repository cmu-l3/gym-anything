#!/bin/bash
# Export script for Social Sharing Configuration task

echo "=== Exporting Social Sharing Config Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Query the configuration table for the specific paths we care about
# We look for values in 'default' scope (scope_id=0) or 'websites' scope if agent set it there.
# To simplify, we pull the most specific value set (highest precedence) if multiple exist,
# but usually agent sets default config.

echo "Querying core_config_data..."

QUERY="SELECT path, value FROM core_config_data WHERE path IN (
    'sendfriend/email/enabled',
    'sendfriend/email/allow_guest',
    'sendfriend/email/max_recipients',
    'sendfriend/email/max_per_hour',
    'wishlist/email/number_limit',
    'wishlist/email/email_identity'
)"

CONFIG_DATA=$(magento_query_headers "$QUERY")

# Process results into a simple JSON key-value object
# Output format from mysql with -B is tab separated.
# We'll use python to parse it safely into JSON to avoid escaping issues.

cat > /tmp/parse_config.py << 'PYEOF'
import sys
import json

lines = sys.stdin.readlines()
config = {}
# Skip header line if present (mysql -B -N doesn't output headers, but magento_query_headers does)
start_idx = 1 if len(lines) > 0 and 'path' in lines[0] else 0

for line in lines[start_idx:]:
    parts = line.strip().split('\t')
    if len(parts) >= 2:
        path = parts[0]
        value = parts[1]
        config[path] = value

print(json.dumps(config))
PYEOF

CONFIG_JSON=$(echo "$CONFIG_DATA" | python3 /tmp/parse_config.py)
rm -f /tmp/parse_config.py

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/social_config_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config": $CONFIG_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/social_config_result.json

echo ""
echo "Exported Configuration:"
echo "$CONFIG_JSON" | jq '.' 2>/dev/null || echo "$CONFIG_JSON"
echo ""
echo "=== Export Complete ==="