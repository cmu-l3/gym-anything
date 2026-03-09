#!/bin/bash
# Setup script for Measure Cell Areas task
# Uses BBBC005 dataset from Broad Bioimage Benchmark Collection

source /workspace/scripts/task_utils.sh

echo "=== Setting up Measure Cell Areas task ==="

# ============================================================
# TASK SETUP REQUIREMENTS:
# - BBBC005 dataset available
# - Fiji launched and ready
# - Sample image pre-opened for the agent
# ============================================================

DATA_DIR="/home/ga/ImageJ_Data"
RAW_DIR="$DATA_DIR/raw"
RESULTS_DIR="$DATA_DIR/results"
BBBC_DIR="/opt/imagej_samples/BBBC005"

mkdir -p "$DATA_DIR"
mkdir -p "$RAW_DIR"
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR"

# Clear previous state
rm -f /tmp/fiji_state.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/Results.csv 2>/dev/null || true
rm -f /tmp/cell_stats.json 2>/dev/null || true
rm -f "$RESULTS_DIR"/*.csv 2>/dev/null || true

# Record initial state for verification
echo "0" > /tmp/initial_cell_count
touch /tmp/task_start_time

# ============================================================
# Verify BBBC005 dataset is available
# ============================================================
echo "Checking for BBBC005 dataset..."

# Find BBBC005 images (they might be in nested directories)
BBBC_IMAGES=$(find "$BBBC_DIR" -name "*.TIF" -o -name "*.tif" 2>/dev/null | head -20)

if [ -z "$BBBC_IMAGES" ]; then
    echo "BBBC005 images not found, attempting download..."

    # Try to download if not present
    mkdir -p "$BBBC_DIR"
    cd /tmp

    wget -q --timeout=120 "https://data.broadinstitute.org/bbbc/BBBC005/BBBC005_v1_images.zip" \
        -O bbbc005_images.zip 2>/dev/null

    if [ -f bbbc005_images.zip ] && [ -s bbbc005_images.zip ]; then
        unzip -q bbbc005_images.zip -d "$BBBC_DIR" 2>/dev/null
        rm -f bbbc005_images.zip
        echo "BBBC005 dataset downloaded"
    else
        echo "WARNING: Could not download BBBC005 dataset"
        echo "Task may not work correctly"
    fi
fi

# Copy a representative sample to user directory
SAMPLE_IMAGE=$(find "$BBBC_DIR" -name "*.TIF" -o -name "*.tif" 2>/dev/null | head -1)
if [ -n "$SAMPLE_IMAGE" ]; then
    mkdir -p "$RAW_DIR/BBBC005"
    # Copy first 10 images for variety
    find "$BBBC_DIR" -name "*.TIF" -o -name "*.tif" 2>/dev/null | head -10 | while read img; do
        cp "$img" "$RAW_DIR/BBBC005/" 2>/dev/null
    done
    chown -R ga:ga "$RAW_DIR/BBBC005"
    echo "Sample images copied to $RAW_DIR/BBBC005/"
fi

# ============================================================
# Kill any existing Fiji instance
# ============================================================
echo "Ensuring clean Fiji state..."
kill_fiji
sleep 2

# ============================================================
# Create macro to open a sample image
# ============================================================
OPEN_MACRO="/tmp/open_bbbc_sample.ijm"

# Find a good sample image (prefer ones with moderate cell density)
SAMPLE_IMAGE=$(find "$RAW_DIR/BBBC005" -name "*.TIF" 2>/dev/null | head -1)
if [ -z "$SAMPLE_IMAGE" ]; then
    SAMPLE_IMAGE=$(find "$BBBC_DIR" -name "*.TIF" 2>/dev/null | head -1)
fi

if [ -n "$SAMPLE_IMAGE" ]; then
    cat > "$OPEN_MACRO" << MACROEOF
// Open BBBC005 sample image
open("$SAMPLE_IMAGE");
wait(2000);
MACROEOF
    chmod 644 "$OPEN_MACRO"
    chown ga:ga "$OPEN_MACRO"
    echo "Created macro to open: $SAMPLE_IMAGE"
else
    # Fallback: just open Fiji without image
    cat > "$OPEN_MACRO" << 'MACROEOF'
// No sample image found
print("Please open an image from ~/ImageJ_Data/raw/BBBC005/");
MACROEOF
    chmod 644 "$OPEN_MACRO"
    chown ga:ga "$OPEN_MACRO"
fi

# ============================================================
# Find Fiji executable
# ============================================================
FIJI_PATH=$(find_fiji_executable)
if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found!"
    exit 1
fi
echo "Found Fiji at: $FIJI_PATH"

# Setup display
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# ============================================================
# ROBUST FIJI LAUNCH WITH RETRY LOGIC
# ============================================================

# Function to launch Fiji and verify it's running
launch_and_verify_fiji() {
    local attempt=$1
    echo "=== Fiji launch attempt $attempt ==="

    # Kill any lingering Fiji processes
    pkill -f "fiji" 2>/dev/null || true
    pkill -f "ImageJ" 2>/dev/null || true
    sleep 2

    # Launch Fiji with the open macro
    echo "Launching Fiji with sample image..."
    su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' -macro '$OPEN_MACRO' > /tmp/fiji_ga.log 2>&1" &
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

    # Wait for image window to appear
    echo "Waiting for image to load..."
    for i in $(seq 1 30); do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "\.tif|SIMCEP|BBBC"; then
            echo "Image window detected after ${i} seconds"
            break
        fi
        sleep 1
    done

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

IMG_WID=$(get_image_window_id)
if [ -n "$IMG_WID" ]; then
    maximize_window "$IMG_WID"
    echo "Image window maximized"
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
echo "TASK: Measure Cell Areas from BBBC005 Dataset"
echo "============================================================"
echo ""
echo "A sample image from the BBBC005 synthetic cell dataset"
echo "should be loaded in Fiji."
echo ""
echo "Your task is to:"
echo ""
echo "1. Process the image for segmentation:"
echo "   - Apply Gaussian blur: Process > Filters > Gaussian Blur"
echo "   - Apply threshold: Image > Adjust > Threshold"
echo ""
echo "2. Separate touching cells:"
echo "   - Process > Binary > Watershed"
echo ""
echo "3. Set measurements:"
echo "   - Analyze > Set Measurements (Area, Perimeter, Circularity)"
echo ""
echo "4. Analyze particles:"
echo "   - Analyze > Analyze Particles"
echo "   - Size: 100-5000, Circularity: 0.3-1.0"
echo "   - Enable 'Display results' and 'Summarize'"
echo ""
echo "5. Report: cell count, average area, average circularity"
echo ""
echo "Data directory: $RAW_DIR/BBBC005"
echo "Results directory: $RESULTS_DIR"
echo "============================================================"
