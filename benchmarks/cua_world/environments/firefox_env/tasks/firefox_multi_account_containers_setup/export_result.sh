#!/bin/bash
echo "=== Exporting task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Check if Firefox is running and force a session sync if possible
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Export containers.json safely
CONTAINERS_EXISTS="false"
CONTAINERS_MTIME=0
if [ -f "$PROFILE_DIR/containers.json" ]; then
    CONTAINERS_EXISTS="true"
    CONTAINERS_MTIME=$(stat -c %Y "$PROFILE_DIR/containers.json" 2>/dev/null || echo "0")
    cp "$PROFILE_DIR/containers.json" /tmp/containers_export.json
    chmod 666 /tmp/containers_export.json
fi

# 4. Decompress sessionstore (mozLz4 format) to JSON
SESSION_DECOMPRESSED="false"
SESSION_FILE=""

# Firefox frequently updates the recovery file in sessionstore-backups while running
if [ -f "$PROFILE_DIR/sessionstore-backups/recovery.jsonlz4" ]; then
    SESSION_FILE="$PROFILE_DIR/sessionstore-backups/recovery.jsonlz4"
elif [ -f "$PROFILE_DIR/sessionstore.jsonlz4" ]; then
    SESSION_FILE="$PROFILE_DIR/sessionstore.jsonlz4"
fi

if [ -n "$SESSION_FILE" ]; then
    cat > /tmp/decompress_mozlz4.py << 'EOF'
import sys
import json
try:
    import lz4.block
except ImportError:
    sys.exit(1)

input_file = sys.argv[1]
output_file = sys.argv[2]

try:
    with open(input_file, 'rb') as f:
        magic = f.read(8)
        if magic == b'mozLz40\0':
            decompressed = lz4.block.decompress(f.read())
            with open(output_file, 'wb') as out:
                out.write(decompressed)
            sys.exit(0)
except Exception as e:
    sys.exit(2)
EOF

    # Try to decompress using python script
    python3 /tmp/decompress_mozlz4.py "$SESSION_FILE" "/tmp/session_export.json" 2>/dev/null
    if [ $? -eq 0 ] && [ -f "/tmp/session_export.json" ]; then
        SESSION_DECOMPRESSED="true"
        chmod 666 /tmp/session_export.json
    fi
fi

# 5. Build summary JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "containers_json_exists": $CONTAINERS_EXISTS,
    "containers_json_mtime": $CONTAINERS_MTIME,
    "session_decompressed": $SESSION_DECOMPRESSED
}
EOF

# Move outputs
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON generated at /tmp/task_result.json"
echo "=== Export complete ==="