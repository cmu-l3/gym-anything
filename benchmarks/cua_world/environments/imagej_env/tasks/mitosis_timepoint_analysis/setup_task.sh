#!/bin/bash
# Setup script for mitosis_timepoint_analysis task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Mitosis Time-Point Analysis Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

# Clear previous results for this specific task
rm -f "$RESULTS_DIR/mitosis_timeseries.csv" 2>/dev/null || true
rm -f /tmp/mitosis_timepoint_analysis_result.json 2>/dev/null || true

# Record baseline
echo "false" > /tmp/initial_mitosis_file_exists

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
echo "Task start: $(date)"

# Kill any existing Fiji
echo "Ensuring clean Fiji state..."
kill_fiji
sleep 2

FIJI_PATH=$(find_fiji_executable)
if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found!"
    exit 1
fi
echo "Found Fiji at: $FIJI_PATH"

export DISPLAY=:1
xhost +local: 2>/dev/null || true

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

WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    focus_window "$WID"
fi
sleep 2

take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Setup Complete ==="
echo ""
echo "================================================================"
echo "TASK: Mitosis Time-Lapse Quantification"
echo "================================================================"
echo ""
echo "Goal: Quantify mitotic cell counts and fluorescent area at"
echo "      each time frame of the Mitosis 5D stack."
echo ""
echo "Target image: File > Open Samples > Mitosis (5D stack)"
echo "  This is a 5D hyperstack: 171x196 px, 2 channels,"
echo "  51 z-slices, 5 time frames."
echo ""
echo "Required measurements (for each of the 5 time frames):"
echo "  - Time frame index"
echo "  - Number of distinct mitotic cells/objects"
echo "  - Total thresholded fluorescent area"
echo ""
echo "At least 4 of the 5 time frames must be measured."
echo ""
echo "Save time-series measurements to:"
echo "  ~/ImageJ_Data/results/mitosis_timeseries.csv"
echo "================================================================"
