#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Measure Star Photometry Result ==="

# ============================================================
# CRITICAL: Query AstroImageJ's ACTUAL state, not just files
# This prevents gaming by creating fake measurement files
# ============================================================

# Take final screenshot BEFORE closing (for VLM verification)
FINAL_SCREENSHOT="/tmp/aij_final_screenshot.png"
take_screenshot "$FINAL_SCREENSHOT"
echo "Final screenshot saved to $FINAL_SCREENSHOT"

# ============================================================
# METHOD 1: Query AstroImageJ via macro interface
# This is the ONLY reliable way to know what's actually loaded
# ============================================================

AIJ_STATE_FILE="/tmp/aij_state.json"
AIJ_QUERY_MACRO="/tmp/query_aij_state.ijm"

# Create macro to query AstroImageJ state
cat > "$AIJ_QUERY_MACRO" << 'MACROEOF'
// Query AstroImageJ state and save to JSON

// Check if any images are open
numImages = nImages;

// Get info about current image if one is open
currentTitle = "";
currentDir = "";
imageWidth = 0;
imageHeight = 0;
if (numImages > 0) {
    currentTitle = getTitle();
    currentDir = getInfo("image.directory");
    imageWidth = getWidth();
    imageHeight = getHeight();
}

// Check measurements table
numResults = nResults;
measurementData = "";
if (numResults > 0) {
    // Get the last measurement row
    for (i = 0; i < numResults && i < 10; i++) {
        // Try to get common aperture photometry columns
        x = 0; y = 0; flux = 0;
        if (isOpen("Results")) {
            x = getResult("X", i);
            y = getResult("Y", i);
            // AstroImageJ uses different column names
            flux = getResult("Source-Sky", i);
            if (isNaN(flux)) flux = getResult("Int_Flux", i);
            if (isNaN(flux)) flux = getResult("Tot_C_Cnts", i);
            if (isNaN(flux)) flux = getResult("Mean", i);
        }
        measurementData = measurementData + x + "," + y + "," + flux + ";";
    }
}

// Check if aperture photometry tool has been used
// (AstroImageJ sets specific ROIs when doing aperture photometry)
roiCount = 0;
if (roiManager("count") > 0) {
    roiCount = roiManager("count");
}

// Write state to file
f = File.open("/tmp/aij_state.json");
print(f, "{");
print(f, "  \"num_images\": " + numImages + ",");
print(f, "  \"current_image_title\": \"" + currentTitle + "\",");
print(f, "  \"current_image_dir\": \"" + currentDir + "\",");
print(f, "  \"image_width\": " + imageWidth + ",");
print(f, "  \"image_height\": " + imageHeight + ",");
print(f, "  \"num_results\": " + numResults + ",");
print(f, "  \"measurement_data\": \"" + measurementData + "\",");
print(f, "  \"roi_count\": " + roiCount);
print(f, "}");
File.close(f);

print("AIJ state exported to /tmp/aij_state.json");
MACROEOF

# Try to run the macro in AstroImageJ
AIJ_MACRO_SUCCESS="false"
NUM_IMAGES=0
CURRENT_IMAGE=""
NUM_RESULTS=0
MEASUREMENT_DATA=""

if is_aij_running; then
    echo "AstroImageJ is running, attempting to query state via macro..."

    # Method 1: Try using ImageJ's macro runner
    # AstroImageJ can run macros via command line or through the GUI

    # First, try the direct macro approach via xdotool
    # Open Plugins > Macros > Run...
    WID=$(get_aij_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        sleep 1

        # Try running macro via menu: Plugins > Macros > Run...
        DISPLAY=:1 xdotool key alt+p 2>/dev/null  # Plugins menu
        sleep 0.3
        DISPLAY=:1 xdotool key m 2>/dev/null  # Macros submenu
        sleep 0.3
        DISPLAY=:1 xdotool key r 2>/dev/null  # Run...
        sleep 1

        # Type the macro path and run
        DISPLAY=:1 xdotool type "$AIJ_QUERY_MACRO"
        sleep 0.5
        DISPLAY=:1 xdotool key Return
        sleep 2

        # Check if the state file was created
        if [ -f "$AIJ_STATE_FILE" ]; then
            AIJ_MACRO_SUCCESS="true"
            echo "Macro executed successfully"
            cat "$AIJ_STATE_FILE"

            # Parse the state file
            NUM_IMAGES=$(python3 -c "import json; print(json.load(open('$AIJ_STATE_FILE')).get('num_images', 0))" 2>/dev/null || echo "0")
            CURRENT_IMAGE=$(python3 -c "import json; print(json.load(open('$AIJ_STATE_FILE')).get('current_image_title', ''))" 2>/dev/null || echo "")
            NUM_RESULTS=$(python3 -c "import json; print(json.load(open('$AIJ_STATE_FILE')).get('num_results', 0))" 2>/dev/null || echo "0")
            MEASUREMENT_DATA=$(python3 -c "import json; print(json.load(open('$AIJ_STATE_FILE')).get('measurement_data', ''))" 2>/dev/null || echo "")
        fi
    fi
fi

# ============================================================
# METHOD 2: Check window titles for evidence of loaded images
# (Fallback if macro method fails)
# ============================================================

WINDOWS_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
FITS_WINDOW_FOUND="false"
FITS_WINDOW_TITLE=""

# Check if any window title contains FITS file indicators
if echo "$WINDOWS_LIST" | grep -qi "fits\|wfpc\|hst\|uit\|starfield"; then
    FITS_WINDOW_FOUND="true"
    FITS_WINDOW_TITLE=$(echo "$WINDOWS_LIST" | grep -i "fits\|wfpc\|hst\|uit\|starfield" | head -1 | cut -d' ' -f5-)
fi

# ============================================================
# METHOD 3: Check for Results window (AstroImageJ creates this)
# ============================================================

RESULTS_WINDOW_FOUND="false"
if echo "$WINDOWS_LIST" | grep -qi "Results\|Measurements\|Photometry"; then
    RESULTS_WINDOW_FOUND="true"
fi

# ============================================================
# Check measurement files (but DON'T trust them as sole evidence)
# ============================================================

MEASUREMENT_DIR="/home/ga/AstroImages/measurements"
INITIAL_COUNT=$(cat /tmp/initial_measurement_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(ls -1 "$MEASUREMENT_DIR"/*.txt "$MEASUREMENT_DIR"/*.csv "$MEASUREMENT_DIR"/*.tbl 2>/dev/null | wc -l || echo "0")

NEW_MEASUREMENT_FILE=""
if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
    NEW_MEASUREMENT_FILE=$(ls -t "$MEASUREMENT_DIR"/*.txt "$MEASUREMENT_DIR"/*.csv "$MEASUREMENT_DIR"/*.tbl 2>/dev/null | head -1)
fi

# ============================================================
# Close AstroImageJ
# ============================================================

close_astroimagej

# ============================================================
# Create comprehensive result JSON
# ============================================================

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "aij_macro_success": $AIJ_MACRO_SUCCESS,
    "num_images_loaded": $NUM_IMAGES,
    "current_image_title": "$CURRENT_IMAGE",
    "num_measurements": $NUM_RESULTS,
    "measurement_data": "$MEASUREMENT_DATA",
    "fits_window_found": $FITS_WINDOW_FOUND,
    "fits_window_title": "$FITS_WINDOW_TITLE",
    "results_window_found": $RESULTS_WINDOW_FOUND,
    "new_measurement_file": "$NEW_MEASUREMENT_FILE",
    "initial_file_count": $INITIAL_COUNT,
    "current_file_count": $CURRENT_COUNT,
    "screenshot_path": "$FINAL_SCREENSHOT",
    "windows_list": "$(echo "$WINDOWS_LIST" | tr '\n' '|')",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="
