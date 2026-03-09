#!/bin/bash
# Shared utilities for UrbanSim tasks

# Activate virtualenv
activate_venv() {
    source /opt/urbansim_env/bin/activate
}

# Screenshot function
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$path" 2>/dev/null || \
    DISPLAY=:1 scrot "$path" 2>/dev/null || true
}

# Check if Jupyter Lab is running
is_jupyter_running() {
    pgrep -f "jupyter-lab" > /dev/null 2>&1
}

# Wait for Jupyter Lab to be ready
wait_for_jupyter() {
    local timeout=${1:-60}
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if curl -s http://localhost:8888/api > /dev/null 2>&1; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

# Check if Firefox is running
is_firefox_running() {
    pgrep -f "firefox" > /dev/null 2>&1
}

# Get Firefox window ID
get_firefox_window() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|Mozilla\|jupyter" | head -1 | awk '{print $1}'
}

# Focus Firefox window
focus_firefox() {
    local wid=$(get_firefox_window)
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -i -a "$wid"
        return 0
    fi
    return 1
}

# Maximize Firefox window
maximize_firefox() {
    local wid=$(get_firefox_window)
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz
        return 0
    fi
    return 1
}

# Run Python script using the UrbanSim virtualenv
run_python() {
    local script="$1"
    local output_file="${2:-/tmp/python_output.txt}"
    /opt/urbansim_env/bin/python "$script" > "$output_file" 2>&1
    cat "$output_file"
}

# Run Python expression
run_python_expr() {
    local expr="$1"
    /opt/urbansim_env/bin/python -c "$expr" 2>/dev/null
}

# Execute a Jupyter notebook programmatically
run_notebook() {
    local notebook="$1"
    local output="${2:-${notebook%.ipynb}_executed.ipynb}"
    /opt/urbansim_env/bin/jupyter nbconvert --to notebook --execute \
        --ExecutePreprocessor.timeout=300 \
        --output "$output" "$notebook" 2>/dev/null
}

# Wait for file to exist
wait_for_file() {
    local file="$1"
    local timeout=${2:-60}
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if [ -f "$file" ]; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

# Check if file was modified after a timestamp
file_modified_after() {
    local file="$1"
    local timestamp="$2"
    if [ ! -f "$file" ]; then
        return 1
    fi
    local file_mtime=$(stat -c %Y "$file" 2>/dev/null)
    if [ "$file_mtime" -gt "$timestamp" ]; then
        return 0
    fi
    return 1
}

# Safe xdotool wrapper
safe_xdotool() {
    DISPLAY=:1 xdotool "$@" 2>/dev/null || true
}
