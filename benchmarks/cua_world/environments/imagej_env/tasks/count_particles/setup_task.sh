#!/bin/bash
# Setup script for Particle Counting task
# Launches Fiji and prepares environment for particle analysis

source /workspace/scripts/task_utils.sh

echo "=== Setting up Particle Counting task ==="

# ============================================================
# TASK SETUP REQUIREMENTS:
# - Fiji launched and ready
# - No images pre-opened (agent must open sample)
# - Clean Results table
# ============================================================

DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

mkdir -p "$DATA_DIR"
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR"

# Clear previous state
rm -f /tmp/fiji_state.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/Results.csv 2>/dev/null || true
rm -f /tmp/summary_stats.json 2>/dev/null || true
rm -f "$RESULTS_DIR"/*.csv 2>/dev/null || true

# Record initial state for verification
echo "0" > /tmp/initial_particle_count
touch /tmp/task_start_time

# ============================================================
# Kill any existing Fiji instance
# ============================================================
echo "Ensuring clean Fiji state..."
kill_fiji
sleep 2

# ============================================================
# ROBUST FIJI LAUNCH WITH RETRY LOGIC
# ============================================================

# Find Fiji executable
FIJI_PATH=$(find_fiji_executable)
if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found!"
    exit 1
fi
echo "Found Fiji at: $FIJI_PATH"

# Setup display
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Function to launch Fiji and verify it's running
launch_and_verify_fiji() {
    local attempt=$1
    echo "=== Fiji launch attempt $attempt ==="

    # Kill any lingering Fiji processes
    pkill -f "fiji" 2>/dev/null || true
    pkill -f "ImageJ" 2>/dev/null || true
    sleep 2

    # Launch Fiji
    echo "Launching Fiji..."
    su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /tmp/fiji_ga.log 2>&1" &
    FIJI_PID=$!

    # Wait for Fiji window to appear (up to 90 seconds)
    echo "Waiting for Fiji window..."
    local started=false
    for i in $(seq 1 90); do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ImageJ\|Fiji"; then
            echo "Fiji window detected after ${i} seconds"
            started=true
            break
        fi
        # Also check if process is still running
        if ! ps -p $FIJI_PID > /dev/null 2>&1; then
            echo "Fiji process died, checking log..."
            cat /tmp/fiji_ga.log 2>/dev/null | tail -20
            return 1
        fi
        sleep 1
    done

    if [ "$started" = false ]; then
        echo "Fiji window not detected within timeout"
        return 1
    fi

    # Wait for GUI to fully initialize
    echo "Waiting for Fiji GUI to initialize..."
    sleep 10

    # Handle ImageJ Updater dialog if it appears
    echo "Checking for ImageJ Updater dialog..."
    for dismiss_attempt in 1 2 3 4 5; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Updater"; then
            echo "Updater dialog detected (dismiss attempt $dismiss_attempt)"

            UPDATER_WID=$(DISPLAY=:1 wmctrl -l | grep -i "Updater" | head -1 | awk '{print $1}')
            if [ -n "$UPDATER_WID" ]; then
                # Focus and dismiss
                DISPLAY=:1 wmctrl -i -a "$UPDATER_WID" 2>/dev/null || true
                sleep 0.5
                DISPLAY=:1 xdotool key Return
                sleep 1

                # Check if dismissed
                if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Updater"; then
                    echo "Updater dialog dismissed"
                    break
                fi

                # Try Escape as fallback
                DISPLAY=:1 xdotool key Escape
                sleep 1
            fi
        else
            break
        fi
    done

    # Wait for any dialogs to clear
    sleep 3

    # CRITICAL: Final verification that Fiji main window exists
    echo "Final verification of Fiji window..."
    local fiji_windows=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ImageJ\|Fiji" | grep -v "Updater" | wc -l)
    if [ "$fiji_windows" -gt 0 ]; then
        echo "VERIFIED: Fiji is running ($fiji_windows windows)"
        return 0
    else
        echo "FAILED: No Fiji main window found"
        return 1
    fi
}

# ============================================================
# MAIN LAUNCH LOOP - Up to 3 attempts
# ============================================================
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

# ============================================================
# FAIL EXPLICITLY if Fiji never started
# ============================================================
if [ "$FIJI_RUNNING" = false ]; then
    echo "============================================================"
    echo "CRITICAL ERROR: Failed to start Fiji after 3 attempts"
    echo "============================================================"
    echo "Fiji launch log:"
    cat /tmp/fiji_ga.log 2>/dev/null | tail -50
    echo ""
    echo "Window list:"
    DISPLAY=:1 wmctrl -l 2>/dev/null
    echo ""
    # Take screenshot of failed state
    take_screenshot /tmp/fiji_failed_screenshot.png
    echo "Failed state screenshot saved to /tmp/fiji_failed_screenshot.png"
    # EXIT WITH ERROR - do not proceed with broken state
    exit 1
fi

# ============================================================
# Maximize and focus Fiji window
# ============================================================
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    focus_window "$WID"
    echo "Fiji window maximized and focused"
fi

# Wait for everything to settle
sleep 2

# ============================================================
# FINAL VERIFICATION before completing setup
# ============================================================
FINAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ImageJ\|Fiji" | grep -v "Updater")
if [ -z "$FINAL_WINDOWS" ]; then
    echo "ERROR: Fiji disappeared after maximizing!"
    exit 1
fi

echo "CONFIRMED: Fiji is running and ready"
echo "Windows: $FINAL_WINDOWS"

# Take screenshot of initial state
take_screenshot /tmp/task_start_screenshot.png
echo "Task start screenshot captured"

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Count and Measure Particles in Microscopy Image"
echo "============================================================"
echo ""
echo "You have access to Fiji (ImageJ). Your task is to:"
echo ""
echo "1. Open the 'blobs' sample image:"
echo "   File > Open Samples > Blobs (25K)"
echo ""
echo "2. Convert to binary using thresholding:"
echo "   Image > Adjust > Threshold"
echo "   - Apply threshold to separate particles from background"
echo "   - Click 'Apply' to convert to binary"
echo ""
echo "3. IMPORTANT: Invert the binary image (blobs should be white on black):"
echo "   Edit > Invert (or Ctrl+Shift+I)"
echo "   - Analyze Particles counts white objects on black background"
echo ""
echo "4. Analyze the particles:"
echo "   Analyze > Analyze Particles"
echo "   - Enable 'Display results' and 'Summarize'"
echo ""
echo "5. Report the results:"
echo "   - Total particle count"
echo "   - Average particle area"
echo "   - Size range"
echo ""
echo "Results will be saved in: $RESULTS_DIR"
echo "============================================================"
