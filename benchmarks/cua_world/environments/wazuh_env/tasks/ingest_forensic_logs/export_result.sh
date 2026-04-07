#!/bin/bash
echo "=== Exporting Ingest Forensic Logs Result ==="

source /workspace/scripts/task_utils.sh

# Define variables
CONTAINER="${WAZUH_MANAGER_CONTAINER}"
TARGET_FILE="/var/ossec/logs/forensic_import.log"
ATTACKER_IP="192.168.50.44"
TASK_START_ISO=$(cat /tmp/task_start_iso.txt 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%S.000Z")

# 1. Check Configuration in ossec.conf
echo "Checking ossec.conf configuration..."
CONFIG_CHECK_CMD="grep -C 2 '$TARGET_FILE' /var/ossec/etc/ossec.conf"
CONFIG_CONTENT=$(docker exec "$CONTAINER" bash -c "$CONFIG_CHECK_CMD" 2>/dev/null || echo "")

HAS_CONFIG="false"
HAS_FORMAT="false"

if [ -n "$CONFIG_CONTENT" ]; then
    HAS_CONFIG="true"
    if echo "$CONFIG_CONTENT" | grep -q "apache"; then
        HAS_FORMAT="true"
    fi
fi

# 2. Check File Existence and Content inside Container
echo "Checking log file inside container..."
FILE_CHECK=$(docker exec "$CONTAINER" ls -l "$TARGET_FILE" 2>/dev/null || echo "not found")
FILE_CONTENT_COUNT=$(docker exec "$CONTAINER" wc -l "$TARGET_FILE" 2>/dev/null | awk '{print $1}' || echo "0")

FILE_EXISTS="false"
if [[ "$FILE_CHECK" != *"not found"* ]]; then
    FILE_EXISTS="true"
fi

# 3. Query Indexer for Alerts
echo "Querying Wazuh Indexer for alerts..."
# We search for alerts where:
# - timestamp is after task start
# - data.srcip matches attacker IP
# - rule.groups includes sql_injection or web
# - location matches forensic_import.log

QUERY_BODY=$(cat <<EOF
{
  "query": {
    "bool": {
      "must": [
        { "match": { "data.srcip": "$ATTACKER_IP" } },
        { "match": { "location": "$TARGET_FILE" } },
        { "range": { "@timestamp": { "gte": "$TASK_START_ISO" } } }
      ]
    }
  }
}
EOF
)

# Use wazuh_indexer_query utility from task_utils.sh
# endpoint: /wazuh-alerts-*/_search
INDEXER_RESPONSE=$(wazuh_indexer_query "/wazuh-alerts-*/_search?size=10" "$QUERY_BODY")

# Extract alert count and hits using python
ALERTS_JSON=$(echo "$INDEXER_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    hits = data.get('hits', {}).get('hits', [])
    total = data.get('hits', {}).get('total', {}).get('value', 0)
    
    alerts = []
    for hit in hits:
        source = hit.get('_source', {})
        rule = source.get('rule', {})
        alerts.append({
            'rule_id': rule.get('id'),
            'rule_description': rule.get('description'),
            'groups': rule.get('groups', []),
            'full_log': source.get('full_log', '')
        })
    
    print(json.dumps({'count': total, 'alerts': alerts}))
except Exception as e:
    print(json.dumps({'count': 0, 'alerts': [], 'error': str(e)}))
")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Prepare Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "config_exists": $HAS_CONFIG,
    "config_format_correct": $HAS_FORMAT,
    "file_exists_in_container": $FILE_EXISTS,
    "file_line_count": $FILE_CONTENT_COUNT,
    "indexer_results": $ALERTS_JSON,
    "task_start_iso": "$TASK_START_ISO",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move result to readable location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="