#!/bin/bash
source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting broadcast_podcast_stem_delivery Result ==="

# Take final screenshot before altering state
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end_screenshot.png 2>/dev/null || true

# If Ardour is running, trigger a save then kill it
ARDOUR_RUNNING="false"
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    ARDOUR_RUNNING="true"
    WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
        sleep 1
        DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
        sleep 3
    fi
    if command -v kill_ardour &>/dev/null; then
        kill_ardour
    else
        pkill -f "/usr/lib/ardour" 2>/dev/null || true
        sleep 2
        pkill -9 -f "/usr/lib/ardour" 2>/dev/null || true
    fi
fi

sleep 1

SESSION_FILE="/home/ga/Audio/sessions/MyProject/MyProject.ardour"

# Read baseline metrics
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_session_mtime 2>/dev/null || echo "0")
CURRENT_MTIME="0"

if [ -f "$SESSION_FILE" ]; then
    CURRENT_MTIME=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo "0")
fi

SESSION_MODIFIED="false"
if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ]; then
    SESSION_MODIFIED="true"
fi

# Write result JSON (all data collection in one Python script)
python3 << 'PYEOF'
import os
import json

session_dir = "/home/ga/Audio/sessions/MyProject"
session_file = os.path.join(session_dir, "MyProject.ardour")
delivery_dir = "/home/ga/Audio/podcast_delivery"
default_export_dir = os.path.join(session_dir, "export")

# Collect exported WAV files
exports = []
for d in [delivery_dir, default_export_dir]:
    if os.path.isdir(d):
        for f in os.listdir(d):
            if f.lower().endswith('.wav'):
                path = os.path.join(d, f)
                exports.append({
                    'filename': f,
                    'path': path,
                    'size_bytes': os.path.getsize(path),
                    'mtime': os.path.getmtime(path),
                    'directory': d
                })

# Collect snapshot files
snapshots = []
if os.path.isdir(session_dir):
    for f in os.listdir(session_dir):
        if f.endswith('.ardour') and f != 'MyProject.ardour':
            snapshots.append({
                'filename': f,
                'name': f.replace('.ardour', ''),
                'size_bytes': os.path.getsize(os.path.join(session_dir, f))
            })

result = {
    'session_file_exists': os.path.exists(session_file),
    'delivery_dir_exists': os.path.isdir(delivery_dir),
    'exports': exports,
    'snapshots': snapshots,
    'screenshot_path': '/tmp/task_end_screenshot.png'
}

with open('/tmp/_py_export_data.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Merge Python-gathered data with bash-computed timestamps into final JSON
# Using cat heredoc for the bash values (booleans are JSON-safe as lowercase)
PY_DATA=$(cat /tmp/_py_export_data.json 2>/dev/null || echo '{}')
rm -f /tmp/_py_export_data.json

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "initial_mtime": $INITIAL_MTIME,
    "current_mtime": $CURRENT_MTIME,
    "session_modified": $SESSION_MODIFIED,
    "ardour_was_running": $ARDOUR_RUNNING
}
EOF

# Merge the two JSON objects
python3 -c "
import json
with open('$TEMP_JSON') as f:
    base = json.load(f)
with open('/dev/stdin') as f:
    extra = json.load(f)
base.update(extra)
with open('/tmp/task_result.json', 'w') as f:
    json.dump(base, f, indent=2)
" <<< "$PY_DATA"

rm -f "$TEMP_JSON"

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
