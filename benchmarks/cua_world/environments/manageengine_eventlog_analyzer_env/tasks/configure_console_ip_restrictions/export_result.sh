#!/bin/bash
echo "=== Exporting Configure Console IP Restrictions result ==="

source /workspace/scripts/task_utils.sh

# 1. Check if the console is still accessible from localhost (CRITICAL)
# If the agent blocked 127.0.0.1, this curl will fail or timeout.
echo "Checking console accessibility..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 http://localhost:8095/event/index.do || echo "000")
echo "HTTP Status: $HTTP_STATUS"

ACCESSIBLE="false"
if [ "$HTTP_STATUS" == "200" ] || [ "$HTTP_STATUS" == "302" ] || [ "$HTTP_STATUS" == "303" ]; then
    ACCESSIBLE="true"
fi

# 2. Dump Database Configuration
# We look for tables related to trusted hosts or system configuration.
# Note: In ME EventLog Analyzer, this is often stored in SystemConfig or a specific TrustedHost table.
# We dump a few likely candidates to JSON.

echo "Querying database for configuration..."

# Check if Trusted Host feature is enabled in SystemConfig
# Common param names: "am_trusted_host_enabled", "enable_trusted_host", etc.
# We fetch all params containing 'HOST' or 'IP' to be safe.
SYSTEM_CONFIG_DUMP=$(ela_db_query "SELECT param_name, param_value FROM SystemConfig WHERE param_name ILIKE '%HOST%' OR param_name ILIKE '%IP%' OR param_name ILIKE '%SECURE%';")

# Check for a specific TrustedHosts table (schema varies by version, usually contains HOST_NAME or IP_ADDRESS)
# We try to select all from specific table names if they exist
TRUSTED_HOSTS_DUMP=$(ela_db_query "SELECT * FROM TrustedHost;" 2>/dev/null || ela_db_query "SELECT * FROM AllowedIP;" 2>/dev/null || echo "")

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
import sys

try:
    system_config = '''$SYSTEM_CONFIG_DUMP'''
    trusted_hosts = '''$TRUSTED_HOSTS_DUMP'''
    accessible = '$ACCESSIBLE'
    http_status = '$HTTP_STATUS'
    
    # Simple parsing of the pipe-delimited DB output from ela-db-query
    config_dict = {}
    for line in system_config.splitlines():
        if '|' in line:
            parts = line.split('|', 1)
            config_dict[parts[0].strip()] = parts[1].strip()
            
    # Parse trusted hosts list
    host_list = []
    for line in trusted_hosts.splitlines():
        if line.strip():
            host_list.append(line.strip())

    result = {
        'accessible': accessible == 'true',
        'http_status': http_status,
        'system_config': config_dict,
        'trusted_hosts_raw': host_list
    }
    
    print(json.dumps(result, indent=2))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" > "$TEMP_JSON"

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json