#!/bin/bash
echo "=== Exporting ECDIS NMEA Integration Results ==="

# Paths
BC_CONFIG_FILE="/home/ga/.config/Bridge Command/bc5.ini"
SCRIPT_PATH="/home/ga/Desktop/capture_nmea.py"
LOG_PATH="/home/ga/Documents/nmea_raw.log"
REPORT_PATH="/home/ga/Documents/integration_report.txt"

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Extract Configuration Values
# We need to see what the agent set in the INI file
CONF_IP=""
CONF_PORT=""
if [ -f "$BC_CONFIG_FILE" ]; then
    CONF_IP=$(grep -E "^NMEA_UDPAddress" "$BC_CONFIG_FILE" | cut -d'=' -f2 | tr -d '[:space:]')
    CONF_PORT=$(grep -E "^NMEA_UDPPort" "$BC_CONFIG_FILE" | cut -d'=' -f2 | tr -d '[:space:]')
fi

# 3. Check Script Existence and Content
SCRIPT_EXISTS="false"
SCRIPT_CONTENT=""
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    # Read first 50 lines to verify it looks like python code
    SCRIPT_CONTENT=$(head -n 50 "$SCRIPT_PATH" | base64 -w 0)
fi

# 4. Check NMEA Log (The captured data)
LOG_EXISTS="false"
LOG_SAMPLE=""
LOG_SIZE=0
if [ -f "$LOG_PATH" ]; then
    LOG_EXISTS="true"
    LOG_SIZE=$(stat -c %s "$LOG_PATH")
    # Capture the first 20 lines to verify NMEA format in the verifier
    LOG_SAMPLE=$(head -n 20 "$LOG_PATH" | base64 -w 0)
fi

# 5. Check Report
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | base64 -w 0)
fi

# 6. Anti-gaming: Check File Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
LOG_MTIME=0
if [ -f "$LOG_PATH" ]; then
    LOG_MTIME=$(stat -c %Y "$LOG_PATH")
fi

FILE_CREATED_DURING_TASK="false"
if [ "$LOG_MTIME" -ge "$TASK_START" ]; then
    FILE_CREATED_DURING_TASK="true"
fi

# 7. Create Result JSON
# Using python to safely construct JSON prevents bash escaping hell
python3 -c "
import json
import os

result = {
    'config': {
        'ip': '${CONF_IP}',
        'port': '${CONF_PORT}'
    },
    'script': {
        'exists': ${SCRIPT_EXISTS},
        'content_b64': '${SCRIPT_CONTENT}'
    },
    'log': {
        'exists': ${LOG_EXISTS},
        'size': ${LOG_SIZE},
        'sample_b64': '${LOG_SAMPLE}',
        'created_during_task': ${FILE_CREATED_DURING_TASK}
    },
    'report': {
        'exists': ${REPORT_EXISTS},
        'content_b64': '${REPORT_CONTENT}'
    }
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# Set permissions so the host can read it
chmod 644 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"