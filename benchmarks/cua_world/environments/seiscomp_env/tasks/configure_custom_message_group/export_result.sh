#!/bin/bash
echo "=== Exporting configure_custom_message_group result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CONFIG_FILE="$SEISCOMP_ROOT/etc/scmaster.cfg"

# Check if scmaster is currently running (service health check)
SCMASTER_STATUS=$(su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH seiscomp status scmaster 2>/dev/null" || echo "failed")
if echo "$SCMASTER_STATUS" | grep -q "is running"; then
    SCMASTER_RUNNING="true"
else
    SCMASTER_RUNNING="false"
fi

# Retrieve the effective/parsed configuration profile
su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH seiscomp exec scmaster --dump-config 2>/dev/null" > /tmp/scmaster_dump.txt

# Create a robust JSON export using Python to prevent bash quoting issues
python3 - <<EOF
import json
import os

result = {
    "task_start": $TASK_START,
    "scmaster_running": $SCMASTER_RUNNING,
    "raw_config_exists": os.path.exists("$CONFIG_FILE"),
    "raw_config_content": "",
    "dump_config_content": "",
    "config_mtime": 0
}

if result["raw_config_exists"]:
    try:
        with open("$CONFIG_FILE", "r") as f:
            result["raw_config_content"] = f.read()
        result["config_mtime"] = int(os.path.getmtime("$CONFIG_FILE"))
    except Exception as e:
        pass

try:
    with open("/tmp/scmaster_dump.txt", "r") as f:
        result["dump_config_content"] = f.read()
except Exception as e:
    pass

# Export to JSON file securely
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
EOF

chmod 666 /tmp/task_result.json

# Take final state screenshot (mandatory for evidence)
take_screenshot /tmp/task_final.png

echo "Result JSON saved to /tmp/task_result.json"
echo "=== Export complete ==="