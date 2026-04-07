#!/bin/bash
echo "=== Exporting Modify Device Properties Result ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ==============================================================================
# Fetch Final Device State
# ==============================================================================
# We re-run the same extraction logic as setup to compare states
cat > /tmp/fetch_final_device.py << 'PYEOF'
import json
import sys
import subprocess

def get_device_info():
    try:
        cmd = ["/usr/local/bin/ela-api", "/event/api/v1/devices", "GET"]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            return None
        data = json.loads(result.stdout)
        
        devices = data.get("devices", data.get("data", []))
        for d in devices:
            ip = d.get("ip", "")
            if ip == "127.0.0.1" or ip == "localhost":
                # Extract fields handling potential API variations
                return {
                    "ip": ip,
                    "display_name": d.get("displayName", d.get("hostName", "")),
                    "description": d.get("description", ""),
                    "location": d.get("location", ""),
                    "status": d.get("status", "")
                }
        return None
    except Exception as e:
        return {"error": str(e)}

info = get_device_info()
print(json.dumps(info if info else {}))
PYEOF

FINAL_STATE_JSON=$(python3 /tmp/fetch_final_device.py)
echo "Final device state: $FINAL_STATE_JSON"

# Retrieve Initial State for comparison
INITIAL_STATE_JSON=$(cat /tmp/initial_device_state.json 2>/dev/null || echo "{}")

# Prepare JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_state": $INITIAL_STATE_JSON,
    "final_state": $FINAL_STATE_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="