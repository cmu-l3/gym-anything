#!/bin/bash
# Setup script for fluorescence_colocalization task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fluorescence Colocalization Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

# Clear previous results for this specific task
rm -f "$RESULTS_DIR/colocalization_results.csv" 2>/dev/null || true
rm -f /tmp/fluorescence_colocalization_result.json 2>/dev/null || true

# Record baseline: no result file exists yet
echo "false" > /tmp/initial_coloc_file_exists

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
# ROBUST FIJI LAUNCH WITH RETRY
# ============================================================
launch_and_verify_fiji() {
    local attempt=$1
    echo "=== Fiji launch attempt $attempt ==="
    pkill -f "fiji\|ImageJ" 2>/dev/null || true
    sleep 2

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

    sleep 10

    # Dismiss ImageJ Updater if it appears
    for d in 1 2 3 4 5; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Updater"; then
            UPDATER_WID=$(DISPLAY=:1 wmctrl -l | grep -i "Updater" | head -1 | awk '{print $1}')
            [ -n "$UPDATER_WID" ] && DISPLAY=:1 wmctrl -i -a "$UPDATER_WID" 2>/dev/null || true
            sleep 0.5
            DISPLAY=:1 xdotool key Return 2>/dev/null || true
            sleep 1
        else
            break
        fi
    done

    sleep 3

    local fiji_count=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ImageJ\|Fiji" | grep -v "Updater" | wc -l)
    [ "$fiji_count" -gt 0 ] && return 0 || return 1
}

FIJI_RUNNING=false
for attempt in 1 2 3; do
    if launch_and_verify_fiji $attempt; then
        FIJI_RUNNING=true
        break
    else
        echo "Attempt $attempt failed, retrying..."
        kill_fiji
        sleep 5
    fi
done

if [ "$FIJI_RUNNING" = false ]; then
    echo "CRITICAL ERROR: Failed to start Fiji after 3 attempts"
    cat /tmp/fiji_ga.log 2>/dev/null | tail -30
    exit 1
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
echo ""
echo "================================================================"
echo "TASK: Fluorescence Colocalization Analysis"
echo "================================================================"
echo ""
echo "Goal: Perform quantitative colocalization analysis between"
echo "      the red and green channels of the Fluorescent Cells"
echo "      sample image."
echo ""
echo "Target image: File > Open Samples > Fluorescent Cells"
echo ""
echo "Required measurements:"
echo "  - Thresholded area of red channel region"
echo "  - Mean intensity of red channel within its thresholded region"
echo "  - Thresholded area of green channel region"
echo "  - Mean intensity of green channel within its thresholded region"
echo "  - Pixel overlap area between the two channels"
echo "  - At least one colocalization coefficient:"
echo "    (Pearson r, Manders M1/M2, or overlap coefficient/IoU)"
echo ""
echo "Save all results to:"
echo "  ~/ImageJ_Data/results/colocalization_results.csv"
echo "================================================================"
