#!/bin/bash
set -e
echo "=== Exporting configure_proxy_settings result ==="

# Define paths
RESULT_JSON="/tmp/task_result.json"
TASK_START_FILE="/tmp/task_start_time.txt"
START_TIME=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ============================================================
# Check 1: Find Proxy Settings in Config Files
# ============================================================
# We look for the specific strings the user was asked to enter
PROXY_HOST="proxy.acmecorp.net"
PROXY_PORT="3128"

HOST_FOUND="false"
PORT_FOUND="false"
CONFIG_FILE_PATH=""
MATCH_CONTENT=""

echo "Searching for proxy settings in config files..."

# Helper function to search directory
search_config() {
    local search_dir="$1"
    if [ -d "$search_dir" ]; then
        # Search for files containing the hostname
        # We use grep -r to find the file
        local matches=$(grep -r "$PROXY_HOST" "$search_dir" 2>/dev/null | head -n 1)
        if [ -n "$matches" ]; then
            # Extract filename (everything before the first :)
            CONFIG_FILE_PATH=$(echo "$matches" | cut -d: -f1)
            MATCH_CONTENT=$(echo "$matches" | cut -d: -f2-)
            HOST_FOUND="true"
            
            # Check if port is also in this file
            if grep -q "$PROXY_PORT" "$CONFIG_FILE_PATH"; then
                PORT_FOUND="true"
            fi
            return 0
        fi
    fi
    return 1
}

# Search standard JStock locations
search_config "/home/ga/.jstock" || \
search_config "/home/ga/.java/.userPrefs" || \
search_config "/home/ga/.java"

# ============================================================
# Check 2: Verify Modification Timestamp (Anti-Gaming)
# ============================================================
FILE_MODIFIED_DURING_TASK="false"

if [ "$HOST_FOUND" = "true" ] && [ -f "$CONFIG_FILE_PATH" ]; then
    FILE_MTIME=$(stat -c %Y "$CONFIG_FILE_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$START_TIME" ]; then
        FILE_MODIFIED_DURING_TASK="true"
        echo "Config file was modified during task."
    else
        echo "WARNING: Config file has old timestamp ($FILE_MTIME < $START_TIME)"
    fi
fi

# ============================================================
# Check 3: Config State Change (Anti-Gaming)
# ============================================================
CONFIG_CHANGED="false"
CURRENT_CHECKSUM=""
# If we found the file, calculate its current checksum
if [ -f "$CONFIG_FILE_PATH" ]; then
    CURRENT_CHECKSUM=$(md5sum "$CONFIG_FILE_PATH" | awk '{print $1}')
    
    # Check if this file was in our initial snapshot
    if grep -q "$CONFIG_FILE_PATH" /tmp/initial_config_checksums.txt 2>/dev/null; then
        INITIAL_CHECKSUM=$(grep "$CONFIG_FILE_PATH" /tmp/initial_config_checksums.txt | awk '{print $1}')
        if [ "$CURRENT_CHECKSUM" != "$INITIAL_CHECKSUM" ]; then
            CONFIG_CHANGED="true"
        fi
    else
        # File is new, so config definitely changed
        CONFIG_CHANGED="true"
    fi
fi

# ============================================================
# Create JSON Result
# ============================================================
# We use python to safely generate JSON to avoid escaping issues
python3 -c "
import json
import os
import sys

data = {
    'host_found': $HOST_FOUND, # Python syntax for bool matches variables if lowercase, fixing below
    'port_found': $PORT_FOUND,
    'file_modified_during_task': $FILE_MODIFIED_DURING_TASK,
    'config_changed': $CONFIG_CHANGED,
    'config_path': '$CONFIG_FILE_PATH',
    'screenshot_path': '/tmp/task_final.png',
    'timestamp': '$START_TIME'
}

# Fix booleans for Python (bash strings to python bools)
# Actually easier to dump the bash strings and parse in verifier, 
# but let's do it clean here
for k, v in data.items():
    if isinstance(v, str) and v.lower() == 'true':
        data[k] = True
    elif isinstance(v, str) and v.lower() == 'false':
        data[k] = False

with open('$RESULT_JSON', 'w') as f:
    json.dump(data, f, indent=2)
"

# Set permissions so verifier can read it
chmod 666 "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="