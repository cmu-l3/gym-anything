#!/bin/bash
echo "=== Exporting resolve_microservice_port_conflict result ==="

# Record end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Gather PM2 status as JSON
pm2 jlist > /tmp/pm2_list.json 2>/dev/null || echo "[]" > /tmp/pm2_list.json

# Gather process running on port 3000
LSOF_OUTPUT=$(lsof -i :3000 -t 2>/dev/null | head -1)
if [ -n "$LSOF_OUTPUT" ]; then
    PORT_PROCESS_CMD=$(ps -p "$LSOF_OUTPUT" -o comm= 2>/dev/null | tail -1 | awk '{print $1}' || echo "unknown")
    PORT_PROCESS_ARGS=$(ps -p "$LSOF_OUTPUT" -o args= 2>/dev/null | tail -1 || echo "unknown")
else
    PORT_PROCESS_CMD="none"
    PORT_PROCESS_ARGS="none"
fi

# Check if rogue script is running
if pgrep -f rogue_analytics.py > /dev/null; then
    ROGUE_RUNNING="true"
else
    ROGUE_RUNNING="false"
fi

# Check config MD5
CONFIG_FILE="/opt/socioboard/socioboard-api/user/config/development.json"
if [ -f "$CONFIG_FILE" ]; then
    CONFIG_MD5_FINAL=$(md5sum "$CONFIG_FILE" | awk '{print $1}')
else
    CONFIG_MD5_FINAL="MISSING"
fi
CONFIG_MD5_INITIAL=$(cat /tmp/config_md5_initial.txt 2>/dev/null || echo "INITIAL_MISSING")

# Export safely using Python to prevent JSON injection issues
export ROGUE_RUNNING PORT_PROCESS_CMD PORT_PROCESS_ARGS CONFIG_MD5_INITIAL CONFIG_MD5_FINAL
python3 << 'PYEOF'
import json, os

result = {
    "rogue_running": os.environ.get("ROGUE_RUNNING") == "true",
    "port_3000_cmd": os.environ.get("PORT_PROCESS_CMD", ""),
    "port_3000_args": os.environ.get("PORT_PROCESS_ARGS", ""),
    "config_md5_initial": os.environ.get("CONFIG_MD5_INITIAL", ""),
    "config_md5_final": os.environ.get("CONFIG_MD5_FINAL", "")
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json /tmp/pm2_list.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="