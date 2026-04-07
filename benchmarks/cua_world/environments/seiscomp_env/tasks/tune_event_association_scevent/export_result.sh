#!/bin/bash
echo "=== Exporting tune_event_association_scevent result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot of the environment
take_screenshot /tmp/task_final_screenshot.png

# 1. Check if scevent is currently running
SCEVENT_RUNNING="false"
if su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
    LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
    seiscomp status scevent 2>/dev/null" | grep -q "is running"; then
    SCEVENT_RUNNING="true"
fi

# 2. Check if scevent was restarted by comparing the PID
INITIAL_PID=$(cat /tmp/initial_scevent_pid.txt 2>/dev/null || echo "0")
CURRENT_PID=$(pgrep -u ga -x scevent | head -n 1 || echo "0")

SCEVENT_RESTARTED="false"
if [ "$CURRENT_PID" != "0" ] && [ "$CURRENT_PID" != "$INITIAL_PID" ]; then
    SCEVENT_RESTARTED="true"
fi
# Alternative validation: if the initial process died but the new one hasn't started,
# or if they stopped and started it manually, the PIDs will differ.

# 3. Check configuration file modification
CONFIG_PATH="/home/ga/seiscomp/etc/scevent.cfg"
CONFIG_EXISTS="false"
CONFIG_MODIFIED="false"

if [ -f "$CONFIG_PATH" ]; then
    CONFIG_EXISTS="true"
    
    # Copy configuration file to /tmp for the verifier script to read safely
    cp "$CONFIG_PATH" /tmp/scevent.cfg.out
    chmod 666 /tmp/scevent.cfg.out
    
    # Check if the file was modified since setup
    INITIAL_MTIME=$(cat /tmp/initial_mtime.txt 2>/dev/null || echo "0")
    CURRENT_MTIME=$(stat -c %Y "$CONFIG_PATH" 2>/dev/null || echo "0")
    if [ "$CURRENT_MTIME" != "$INITIAL_MTIME" ]; then
        CONFIG_MODIFIED="true"
    fi
else
    # Create an empty dummy file so copy_from_env doesn't fail
    touch /tmp/scevent.cfg.out
    chmod 666 /tmp/scevent.cfg.out
fi

# 4. Create the JSON result file (safely mapping via temp file)
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "scevent_running": $SCEVENT_RUNNING,
    "scevent_restarted": $SCEVENT_RESTARTED,
    "initial_pid": "$INITIAL_PID",
    "current_pid": "$CURRENT_PID",
    "config_exists": $CONFIG_EXISTS,
    "config_modified": $CONFIG_MODIFIED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final destination
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "JSON metadata saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="