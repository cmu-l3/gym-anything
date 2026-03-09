#!/bin/bash
# Shared utilities for GMAT environment tasks

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority
export GMAT_ROOT=/opt/GMAT
export LD_LIBRARY_PATH=/opt/GMAT/bin:${LD_LIBRARY_PATH:-}

# Find the GMAT GUI binary (handles versioned names like GMAT-R2022a)
find_gmat_gui() {
    for candidate in /opt/GMAT/bin/GMAT_Beta /opt/GMAT/bin/GMAT-R2022a /opt/GMAT/bin/GMAT-R2020a /opt/GMAT/bin/GMAT-R2025a /opt/GMAT/bin/GMAT; do
        if [ -f "$candidate" ] && file "$candidate" 2>/dev/null | grep -q "ELF"; then
            echo "$candidate"
            return 0
        fi
    done
    # Fallback: search for any GMAT ELF executable in bin/
    find /opt/GMAT/bin -maxdepth 1 -name "GMAT*" -type f -executable 2>/dev/null | while read f; do
        if file "$f" 2>/dev/null | grep -q "ELF"; then echo "$f"; break; fi
    done
}

# Find the GMAT console binary
find_gmat_console() {
    for candidate in /opt/GMAT/bin/GmatConsole /opt/GMAT/bin/GmatConsole-R2022a /opt/GMAT/bin/GmatConsole-R2020a /opt/GMAT/bin/GmatConsole-R2025a; do
        if [ -f "$candidate" ] && [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
}

# Take a screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority import -window root "$path" 2>/dev/null || true
}

# Check if GMAT is running
is_gmat_running() {
    pgrep -f "/opt/GMAT/bin/GMAT" > /dev/null 2>&1
}

# Launch GMAT with an optional script file
launch_gmat() {
    local script_file="${1:-}"
    local gmat_gui
    gmat_gui=$(find_gmat_gui)

    if [ -z "$gmat_gui" ]; then
        echo "ERROR: Could not find GMAT GUI binary" >&2
        return 1
    fi

    # Kill any existing GMAT instances
    pkill -f "/opt/GMAT/bin/GMAT" 2>/dev/null || true
    sleep 2

    if [ -n "$script_file" ]; then
        su - ga -c "cd /opt/GMAT/bin && DISPLAY=:1 LD_LIBRARY_PATH=/opt/GMAT/bin:\${LD_LIBRARY_PATH:-} setsid $gmat_gui '$script_file' > /tmp/gmat_task.log 2>&1 &"
    else
        su - ga -c "cd /opt/GMAT/bin && DISPLAY=:1 LD_LIBRARY_PATH=/opt/GMAT/bin:\${LD_LIBRARY_PATH:-} setsid $gmat_gui > /tmp/gmat_task.log 2>&1 &"
    fi
}

# Wait for GMAT window to appear
wait_for_gmat_window() {
    local timeout=${1:-60}
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        local wid
        wid=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "GMAT" 2>/dev/null | head -1)
        if [ -n "$wid" ]; then
            echo "$wid"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "" >&2
    echo "WARNING: GMAT window did not appear within ${timeout} seconds" >&2
    return 1
}

# Get GMAT window ID
get_gmat_window_id() {
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -i "GMAT" | awk '{print $1}' | head -1
}

# Focus and maximize GMAT window
focus_gmat_window() {
    local wid
    wid=$(get_gmat_window_id)
    if [ -n "$wid" ]; then
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -ia "$wid" 2>/dev/null || true
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -ir "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        return 0
    fi
    return 1
}

# Dismiss any GMAT dialogs (Escape + Enter fallback)
dismiss_gmat_dialogs() {
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Return 2>/dev/null || true
    sleep 0.5
}

# Safe xdotool wrapper
safe_xdotool() {
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool "$@" 2>/dev/null || true
}

# Wait for a process to appear
wait_for_process() {
    local process_pattern="$1"
    local timeout=${2:-30}
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if pgrep -f "$process_pattern" > /dev/null 2>&1; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}

# Write a JSON result file safely
write_result_json() {
    local output_path="$1"
    local json_content="$2"
    local temp_file
    temp_file=$(mktemp /tmp/result.XXXXXX.json)
    echo "$json_content" > "$temp_file"
    rm -f "$output_path" 2>/dev/null || sudo rm -f "$output_path" 2>/dev/null || true
    cp "$temp_file" "$output_path" 2>/dev/null || sudo cp "$temp_file" "$output_path"
    chmod 666 "$output_path" 2>/dev/null || sudo chmod 666 "$output_path" 2>/dev/null || true
    rm -f "$temp_file"
}
