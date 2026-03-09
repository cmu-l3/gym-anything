#!/bin/bash
# Setup script for CTCF Quantification task

source /workspace/scripts/task_utils.sh

echo "=== Setting up CTCF Quantification Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

# Clear previous results for this specific task
rm -f "$RESULTS_DIR/ctcf_results.csv" 2>/dev/null || true
rm -f /tmp/ctcf_quantification_result.json 2>/dev/null || true

# Record task start timestamp (critical for anti-gaming)
date +%s > /tmp/task_start_timestamp
echo "Task start: $(date)"

# ============================================================
# Kill any existing Fiji instance
# ============================================================
echo "Ensuring clean Fiji state..."
kill_fiji
sleep 2

# ============================================================
# Find Fiji executable
# ============================================================
FIJI_PATH=$(find_fiji_executable)
if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found!"
    exit 1
fi
echo "Found Fiji at: $FIJI_PATH"

export DISPLAY=:1
xhost +local: 2>/dev/null || true

# ============================================================
# ROBUST FIJI LAUNCH
# ============================================================
launch_and_verify_fiji() {
    local attempt=$1
    echo "=== Fiji launch attempt $attempt ==="
    pkill -f "fiji\|ImageJ" 2>/dev/null || true
    sleep 2

    # Launch without macro - agent must open the sample
    su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /tmp/fiji_ga.log 2>&1" &

    echo "Waiting for Fiji window..."
    local started=false
    for i in $(seq 1 90); do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ImageJ\|Fiji"; then
            echo "Fiji window detected after ${i}s"
            started=true
            break
        fi
        sleep 1
    done

    [ "$started" = false ] && return 1

    sleep 5

    # Dismiss ImageJ Updater/Welcome if it appears
    for d in 1 2 3; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Updater\|Welcome"; then
            WID=$(DISPLAY=:1 wmctrl -l | grep -i "Updater\|Welcome" | head -1 | awk '{print $1}')
            [ -n "$WID" ] && DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
            sleep 0.5
            DISPLAY=:1 xdotool key Escape 2>/dev/null || true
            sleep 1
        else
            break
        fi
    done

    local fiji_count=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ImageJ\|Fiji" | wc -l)
    [ "$fiji_count" -gt 0 ] && return 0 || return 1
}

# Try launch
if ! launch_and_verify_fiji 1; then
    echo "Retry launch..."
    launch_and_verify_fiji 2
fi

# Maximize and focus Fiji
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    focus_window "$WID"
fi
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Setup Complete ==="
echo "Task: Calculate CTCF for 5+ cells in 'Fluorescent Cells' (Green channel)"
echo "Formula: CTCF = IntDen - (Area * Mean_Background)"
echo "Output: ~/ImageJ_Data/results/ctcf_results.csv"