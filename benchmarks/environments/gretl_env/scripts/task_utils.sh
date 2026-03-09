#!/bin/bash
# Shared utility functions for Gretl environment tasks

export DISPLAY="${DISPLAY:-:1}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/gdm/Xauthority}"

GRETL_DATA_DIR="/home/ga/Documents/gretl_data"
GRETL_OUTPUT_DIR="/home/ga/Documents/gretl_output"
GRETL_MASTER_DATA_DIR="/opt/gretl_data/poe5"

# =====================================================================
# Screenshot utilities
# =====================================================================
take_screenshot() {
    local path="${1:-/tmp/gretl_screenshot.png}"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot "$path" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root "$path" 2>/dev/null || true
}

# =====================================================================
# Gretl window management
# =====================================================================
get_gretl_window() {
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -l 2>/dev/null | grep -i "gretl" | head -1 | awk '{print $1}' || true
}

focus_gretl() {
    local wid
    wid=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -l 2>/dev/null | grep -i "gretl" | head -1 | awk '{print $1}') || true
    if [ -n "$wid" ]; then
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
            wmctrl -i -a "$wid" 2>/dev/null || true
    else
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
            wmctrl -a "gretl" 2>/dev/null || true
    fi
}

maximize_gretl() {
    sleep 1
    # Try by window name patterns
    for name in "gretl" "Gretl"; do
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
            wmctrl -r "$name" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    done
}

wait_for_gretl() {
    local timeout="${1:-60}"
    local elapsed=0
    echo "Waiting for Gretl window (timeout=${timeout}s)..."
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "gretl"; then
            echo "Gretl window detected at ${elapsed}s"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: Gretl window not detected after ${timeout}s"
    return 1
}

is_gretl_running() {
    pgrep -f "gretl" > /dev/null 2>&1
}

kill_gretl() {
    pkill -f "gretl" 2>/dev/null || true
    sleep 2
    pkill -9 -f "gretl" 2>/dev/null || true
    sleep 1
}

# =====================================================================
# Dataset management
# =====================================================================
restore_dataset() {
    local dataset="${1:-food.gdt}"
    local dest="${2:-/home/ga/Documents/gretl_data/$dataset}"

    # Try master data dir first
    if [ -f "$GRETL_MASTER_DATA_DIR/$dataset" ]; then
        cp "$GRETL_MASTER_DATA_DIR/$dataset" "$dest"
        chown ga:ga "$dest"
        chmod 644 "$dest"
        echo "Restored $dataset from master data"
    elif [ -f "$GRETL_DATA_DIR/$dataset" ]; then
        # Already in place
        echo "$dataset already available"
    else
        echo "WARNING: $dataset not found in master data"
        return 1
    fi
}

# =====================================================================
# Launch Gretl with a dataset
# =====================================================================
launch_gretl() {
    local dataset_path="${1:-}"
    local log_file="${2:-/home/ga/gretl_task.log}"

    echo "Launching Gretl${dataset_path:+ with $dataset_path}..."
    xhost +local: 2>/dev/null || true

    if [ -n "$dataset_path" ]; then
        su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
            setsid gretl '$dataset_path' >'$log_file' 2>&1 &"
    else
        su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
            setsid gretl >'$log_file' 2>&1 &"
    fi
}

# =====================================================================
# Standard task setup: kill gretl, restore data, launch with dataset
# =====================================================================
setup_gretl_task() {
    local dataset="${1:-food.gdt}"
    local task_name="${2:-task}"

    echo "=== Setting up $task_name ==="

    # Record start time
    date +%s > /tmp/task_start_time.txt

    # Kill any running instances
    kill_gretl

    # Ensure output directory exists
    mkdir -p "$GRETL_OUTPUT_DIR"
    chown ga:ga "$GRETL_OUTPUT_DIR"

    # Restore clean dataset
    restore_dataset "$dataset" "$GRETL_DATA_DIR/$dataset"

    # Record dataset modification time before task
    stat -c%Y "$GRETL_DATA_DIR/$dataset" > /tmp/dataset_initial_mtime.txt 2>/dev/null || true

    # Launch Gretl with the dataset
    launch_gretl "$GRETL_DATA_DIR/$dataset" "/home/ga/gretl_${task_name}.log"

    # Wait for window
    wait_for_gretl 60 || true

    # Wait a bit more for UI to fully load
    sleep 5

    # Dismiss any dialogs
    for i in {1..3}; do
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
            xdotool key Escape 2>/dev/null || true
        sleep 1
    done

    # Maximize window
    maximize_gretl

    # Focus main window
    focus_gretl

    sleep 1

    # Take initial screenshot
    mkdir -p /tmp/task_evidence
    take_screenshot /tmp/task_evidence/initial_state.png

    echo "=== $task_name setup complete ==="
}
