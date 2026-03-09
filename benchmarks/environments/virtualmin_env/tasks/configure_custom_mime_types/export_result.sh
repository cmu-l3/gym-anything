#!/bin/bash
echo "=== Exporting configure_custom_mime_types result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Timestamp check
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 3. Live HTTP Check
# We perform the verification *inside* the environment using curl
# and export the results to JSON. This avoids 'exec_in_env' issues.

echo "Testing .gcode header..."
# Use curl -I to get headers. grep for Content-Type.
# We look specifically for the expected type.
GCODE_HEADER=$(curl -s -I http://acmecorp.test/verification_test.gcode | grep -i "Content-Type:" | tr -d '\r')
if echo "$GCODE_HEADER" | grep -q "text/x-gcode"; then
    GCODE_PASS="true"
else
    GCODE_PASS="false"
fi
echo "Got: $GCODE_HEADER"

echo "Testing .lua header..."
LUA_HEADER=$(curl -s -I http://acmecorp.test/verification_test.lua | grep -i "Content-Type:" | tr -d '\r')
if echo "$LUA_HEADER" | grep -q "text/x-lua"; then
    LUA_PASS="true"
else
    LUA_PASS="false"
fi
echo "Got: $LUA_HEADER"

# 4. Configuration File Check
APACHE_CONFIG="/etc/apache2/sites-available/acmecorp.test.conf"
CONFIG_MODIFIED="false"
CONFIG_HAS_DIRECTIVES="false"

if [ -f "$APACHE_CONFIG" ]; then
    # Check modification time
    CONFIG_MTIME=$(stat -c %Y "$APACHE_CONFIG" 2>/dev/null || echo "0")
    if [ "$CONFIG_MTIME" -gt "$TASK_START" ]; then
        CONFIG_MODIFIED="true"
    fi

    # Check content for directives
    # We look for AddType or similar directives
    if grep -E "AddType.*text/x-gcode.*\.gcode" "$APACHE_CONFIG" && \
       grep -E "AddType.*text/x-lua.*\.lua" "$APACHE_CONFIG"; then
        CONFIG_HAS_DIRECTIVES="true"
    fi
fi

# 5. App State Check
APP_RUNNING="false"
if firefox_is_running; then
    APP_RUNNING="true"
fi

# 6. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $CURRENT_TIME,
    "gcode_check_passed": $GCODE_PASS,
    "gcode_header_actual": "$(json_escape "$GCODE_HEADER")",
    "lua_check_passed": $LUA_PASS,
    "lua_header_actual": "$(json_escape "$LUA_HEADER")",
    "config_modified_during_task": $CONFIG_MODIFIED,
    "config_has_directives": $CONFIG_HAS_DIRECTIVES,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="