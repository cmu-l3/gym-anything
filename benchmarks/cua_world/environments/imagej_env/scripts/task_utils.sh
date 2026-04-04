#!/bin/bash
# Shared utilities for ImageJ/Fiji tasks

# Screenshot function with fallbacks
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || \
    echo "Could not take screenshot"
}

# Get Fiji/ImageJ window ID
get_fiji_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "ImageJ|Fiji" | head -1 | awk '{print $1}'
}

# Get any image window ID
get_image_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "\.tif|\.png|\.jpg|blobs|cells|stack" | head -1 | awk '{print $1}'
}

# Focus a window by ID
focus_window() {
    local wid="$1"
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null || true
    fi
}

# Maximize a window by ID
maximize_window() {
    local wid="$1"
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
}

# Wait for Fiji to start
wait_for_fiji() {
    local timeout="${1:-60}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ImageJ\|Fiji"; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

# Wait for an image window to appear
wait_for_image_window() {
    local timeout="${1:-30}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "\.tif|\.png|\.jpg|blobs|cells|sample"; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

# Find Fiji executable
find_fiji_executable() {
    for path in \
        "/usr/local/bin/fiji" \
        "/opt/fiji/Fiji.app/ImageJ-linux64" \
        "/opt/fiji/ImageJ-linux64"; do
        if [ -x "$path" ]; then
            echo "$path"
            return 0
        fi
    done
    return 1
}

# Launch Fiji with optional macro
launch_fiji() {
    local macro_file="$1"

    FIJI_PATH=$(find_fiji_executable)
    if [ -z "$FIJI_PATH" ]; then
        echo "ERROR: Fiji not found"
        return 1
    fi

    export DISPLAY=:1
    xhost +local: 2>/dev/null || true
    export _JAVA_OPTIONS="-Xmx4g"

    if [ -n "$macro_file" ] && [ -f "$macro_file" ]; then
        "$FIJI_PATH" -macro "$macro_file" > /tmp/fiji.log 2>&1 &
    else
        "$FIJI_PATH" > /tmp/fiji.log 2>&1 &
    fi

    echo $!
}

# Kill Fiji
kill_fiji() {
    pkill -f "fiji\|Fiji\|ImageJ" 2>/dev/null || true
}

# Get measurement count from Results table
get_measurement_count() {
    local results_file="${1:-/tmp/Results.csv}"
    if [ -f "$results_file" ]; then
        wc -l < "$results_file" | xargs
    else
        echo "0"
    fi
}

# Check if Results window is open
check_results_window() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Results"
}

# Check if a specific tool is selected (by window title or status)
check_tool_selected() {
    local tool_name="$1"
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$tool_name"
}

# Run an ImageJ macro
run_fiji_macro() {
    local macro_code="$1"
    local temp_macro=$(mktemp /tmp/macro.XXXXXX.ijm)
    echo "$macro_code" > "$temp_macro"

    FIJI_PATH=$(find_fiji_executable)
    if [ -n "$FIJI_PATH" ]; then
        "$FIJI_PATH" -macro "$temp_macro" > /tmp/macro_output.log 2>&1
    fi

    rm -f "$temp_macro"
}

# Export function for Python scripts
export_functions() {
    export -f take_screenshot
    export -f get_fiji_window_id
    export -f get_image_window_id
    export -f focus_window
    export -f maximize_window
    export -f wait_for_fiji
    export -f wait_for_image_window
    export -f find_fiji_executable
    export -f launch_fiji
    export -f kill_fiji
    export -f get_measurement_count
    export -f check_results_window
}
