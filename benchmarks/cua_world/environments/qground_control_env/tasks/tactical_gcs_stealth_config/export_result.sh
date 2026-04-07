#!/bin/bash
echo "=== Exporting tactical_gcs_stealth_config result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Check if QGC is still running
APP_CLOSED_BY_AGENT="false"
if pgrep -f "AppImage" > /dev/null || pgrep -f "QGroundControl" > /dev/null; then
    echo "QGC is still running. Agent did not close it."
    # Gracefully close it to flush settings
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -c "QGroundControl" 2>/dev/null || true
    sleep 3
    pkill -f "QGroundControl" 2>/dev/null || true
    sleep 2
else
    echo "QGC is closed. Agent followed instructions."
    APP_CLOSED_BY_AGENT="true"
fi

INI_FILE="/home/ga/.config/QGroundControl/QGroundControl.ini"
INI_MTIME=$(stat -c%Y "$INI_FILE" 2>/dev/null || echo "0")
MODIFIED_DURING_TASK="false"
if [ "$INI_MTIME" -ge "$TASK_START" ]; then
    MODIFIED_DURING_TASK="true"
fi

# Parse INI using Python regex (handles QGC's specific INI format cleanly)
python3 << 'PYEOF' > /tmp/ini_data.json
import json, re, os

ini_path = '/home/ga/.config/QGroundControl/QGroundControl.ini'
result = {
    'qgcTheme': '',
    'muteAudio': '',
    'MapProvider': '',
    'VideoSource': '',
    'rtspUrl': ''
}

if os.path.exists(ini_path):
    try:
        with open(ini_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            
            m = re.search(r'^qgcTheme=(.*)$', content, re.MULTILINE)
            if m: result['qgcTheme'] = m.group(1).strip()
            
            m = re.search(r'^muteAudio=(.*)$', content, re.MULTILINE)
            if m: result['muteAudio'] = m.group(1).strip()
            
            m = re.search(r'^MapProvider=(.*)$', content, re.MULTILINE)
            if m: result['MapProvider'] = m.group(1).strip()
            
            m = re.search(r'^VideoSource=(.*)$', content, re.MULTILINE)
            if m: result['VideoSource'] = m.group(1).strip()
            
            m = re.search(r'^rtspUrl=(.*)$', content, re.MULTILINE)
            if m: result['rtspUrl'] = m.group(1).strip()
            
    except Exception as e:
        result['error'] = str(e)

print(json.dumps(result))
PYEOF

INI_DATA=$(cat /tmp/ini_data.json 2>/dev/null || echo "{}")

cat > /tmp/task_result.json << JSONEOF
{
    "app_closed_by_agent": $( [ "$APP_CLOSED_BY_AGENT" = "true" ] && echo "true" || echo "false" ),
    "ini_modified": $( [ "$MODIFIED_DURING_TASK" = "true" ] && echo "true" || echo "false" ),
    "ini_data": $INI_DATA
}
JSONEOF

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="