#!/bin/bash
# Shared utilities for all OpenRocket tasks

OPENROCKET_JAR="/opt/openrocket/OpenRocket.jar"
JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
ROCKETS_DIR="/home/ga/Documents/rockets"
EXPORTS_DIR="/home/ga/Documents/exports"

# Take a screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot "$path" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority import -window root "$path" 2>/dev/null || true
    echo "$path"
}

# Check if OpenRocket is running
is_openrocket_running() {
    pgrep -f "OpenRocket.jar" > /dev/null 2>&1
}

# Launch OpenRocket with optional .ork file argument
launch_openrocket() {
    local file_arg="${1:-}"
    local java_cmd="export DISPLAY=:1 JAVA_HOME=$JAVA_HOME; java -Xms512m -Xmx2048m -jar $OPENROCKET_JAR"
    if [ -n "$file_arg" ]; then
        java_cmd="$java_cmd '$file_arg'"
    fi
    java_cmd="$java_cmd > /tmp/openrocket_task.log 2>&1 &"
    su - ga -c "setsid bash -c '$java_cmd'"
}

# Wait for OpenRocket window to appear
wait_for_openrocket() {
    local timeout="${1:-60}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "openrocket\|rocket"; then
            echo "OpenRocket window detected after ${elapsed}s"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "WARNING: OpenRocket window not detected within ${timeout}s"
    return 1
}

# Focus and maximize the OpenRocket window
focus_openrocket_window() {
    local WID
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "openrocket\|rocket" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        return 0
    fi
    return 1
}

# Dismiss dialogs by pressing Escape multiple times
dismiss_dialogs() {
    local count="${1:-3}"
    for i in $(seq 1 "$count"); do
        sleep 1
        DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    done
}

# List .ork files in a directory
list_rocket_files() {
    local dir="${1:-$ROCKETS_DIR}"
    ls "$dir"/*.ork 2>/dev/null
}

# Count .ork files
count_rocket_files() {
    local dir="${1:-$ROCKETS_DIR}"
    ls "$dir"/*.ork 2>/dev/null | wc -l
}

# Write result JSON safely
write_result_json() {
    local content="$1"
    local result_file="${2:-/tmp/task_result.json}"
    local TEMP
    TEMP=$(mktemp /tmp/result.XXXXXX.json)
    echo "$content" > "$TEMP"
    rm -f "$result_file" 2>/dev/null || sudo rm -f "$result_file" 2>/dev/null || true
    cp "$TEMP" "$result_file" 2>/dev/null || sudo cp "$TEMP" "$result_file"
    chmod 666 "$result_file" 2>/dev/null || sudo chmod 666 "$result_file" 2>/dev/null || true
    rm -f "$TEMP"
    echo "$result_file"
}

# Get MD5 hash of a file
file_md5() {
    local filepath="$1"
    if [ -f "$filepath" ]; then
        md5sum "$filepath" | awk '{print $1}'
    else
        echo ""
    fi
}

# Check if a file is a copy of any known rocket file
is_copy_of_known() {
    local filepath="$1"
    local target_md5
    target_md5=$(file_md5 "$filepath")
    if [ -z "$target_md5" ]; then
        echo "false"
        return
    fi
    for known_file in "$ROCKETS_DIR"/*.ork; do
        if [ -f "$known_file" ]; then
            local known_md5
            known_md5=$(file_md5 "$known_file")
            if [ "$target_md5" = "$known_md5" ]; then
                echo "true"
                return
            fi
        fi
    done
    echo "false"
}
