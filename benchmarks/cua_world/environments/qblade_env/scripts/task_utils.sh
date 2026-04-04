#!/bin/bash
# Shared utilities for all QBlade tasks

# Screenshot function
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Check if QBlade is running
is_qblade_running() {
    pgrep -c -f "[Qq][Bb]lade" 2>/dev/null || echo "0"
}

# Find QBlade binary path
find_qblade_binary() {
    local QBLADE_BIN=$(find /opt/qblade -name "QBlade*" -type f -executable 2>/dev/null | head -1)
    if [ -z "$QBLADE_BIN" ]; then
        QBLADE_BIN=$(find /opt/qblade -name "QBlade*" -type f 2>/dev/null | grep -iv '\.txt\|\.pdf\|\.md\|\.dll' | head -1)
    fi
    echo "$QBLADE_BIN"
}

# Launch QBlade with a specific file
launch_qblade() {
    local FILE_ARG="${1:-}"
    local QBLADE_BIN=$(find_qblade_binary)

    if [ -z "$QBLADE_BIN" ]; then
        echo "ERROR: QBlade binary not found"
        return 1
    fi

    local QBLADE_DIR=$(dirname "$QBLADE_BIN")

    if [ -n "$FILE_ARG" ]; then
        su - ga -c "export DISPLAY=:1; export LD_LIBRARY_PATH='$QBLADE_DIR':\${LD_LIBRARY_PATH:-}; export QT_QPA_PLATFORM=xcb; cd '$QBLADE_DIR' && '$QBLADE_BIN' '$FILE_ARG' > /tmp/qblade_task.log 2>&1 &"
    else
        su - ga -c "export DISPLAY=:1; export LD_LIBRARY_PATH='$QBLADE_DIR':\${LD_LIBRARY_PATH:-}; export QT_QPA_PLATFORM=xcb; cd '$QBLADE_DIR' && '$QBLADE_BIN' > /tmp/qblade_task.log 2>&1 &"
    fi
}

# Wait for QBlade window to appear
wait_for_qblade() {
    local timeout="${1:-30}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "qblade"; then
            echo "QBlade window detected"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: QBlade window not detected within ${timeout}s"
    return 1
}

# List QBlade project files (.wpa)
list_project_files() {
    local dir="${1:-/home/ga/Documents/projects}"
    find "$dir" -name "*.wpa" -type f 2>/dev/null
}

# List airfoil files (.dat)
list_airfoil_files() {
    local dir="${1:-/home/ga/Documents/airfoils}"
    find "$dir" -name "*.dat" -type f 2>/dev/null
}

# Create JSON result with permission-safe writing
write_result_json() {
    local json_content="$1"
    local output_file="${2:-/tmp/task_result.json}"

    TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
    echo "$json_content" > "$TEMP_JSON"

    rm -f "$output_file" 2>/dev/null || sudo rm -f "$output_file" 2>/dev/null || true
    cp "$TEMP_JSON" "$output_file" 2>/dev/null || sudo cp "$TEMP_JSON" "$output_file"
    chmod 666 "$output_file" 2>/dev/null || sudo chmod 666 "$output_file" 2>/dev/null || true
    rm -f "$TEMP_JSON"

    echo "Result saved to $output_file"
    cat "$output_file"
}
