#!/bin/bash
# Export script for Particle Counting task
# Extracts analysis results from Fiji for verification

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Particle Counting Results ==="

# Take final screenshot
FINAL_SCREENSHOT="/tmp/fiji_final_screenshot.png"
take_screenshot "$FINAL_SCREENSHOT" 2>/dev/null || DISPLAY=:1 scrot "$FINAL_SCREENSHOT" 2>/dev/null || true
echo "Final screenshot saved to $FINAL_SCREENSHOT"

# ============================================================
# Get window list (reliable signal)
# ============================================================
WINDOWS_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
echo "Windows: $WINDOWS_LIST"

# ============================================================
# Detect what's visible
# ============================================================
RESULTS_WINDOW="false"
if echo "$WINDOWS_LIST" | grep -qi "Results"; then
    RESULTS_WINDOW="true"
    echo "Results window detected"
fi

SUMMARY_WINDOW="false"
if echo "$WINDOWS_LIST" | grep -qi "Summary"; then
    SUMMARY_WINDOW="true"
    echo "Summary window detected"
fi

IMAGE_WINDOW="false"
IMAGE_NAME=""
if echo "$WINDOWS_LIST" | grep -qiE "blobs|\.tif|\.png|\.gif"; then
    IMAGE_WINDOW="true"
    IMAGE_NAME=$(echo "$WINDOWS_LIST" | grep -iE "blobs|\.tif|\.png|\.gif" | head -1 | sed 's/.*  //')
    echo "Image window detected: $IMAGE_NAME"
fi

THRESHOLD_APPLIED="false"
if echo "$WINDOWS_LIST" | grep -qi "binary\|B&W\|Threshold"; then
    THRESHOLD_APPLIED="true"
    echo "Threshold/Binary image detected"
fi

# ============================================================
# Find Results files
# ============================================================
echo ""
echo "=== Searching for Results files ==="

SEARCH_DIRS="/home/ga/ImageJ_Data/results /home/ga /home/ga/Desktop /tmp"

RESULTS_FILE=""
SUMMARY_FILE=""

# ImageJ saves Results as CSV or can export in various formats
for dir in $SEARCH_DIRS; do
    if [ -d "$dir" ]; then
        # Look for Results files
        found=$(find "$dir" -maxdepth 2 -type f \( \
            -name "Results*.csv" -o \
            -name "Results*.txt" -o \
            -name "Results*.xls" -o \
            -name "*particles*.csv" -o \
            -name "*measurements*.csv" \
        \) -newer /tmp/task_start_time 2>/dev/null | head -3)

        if [ -n "$found" ]; then
            echo "Found in $dir:"
            echo "$found"

            if [ -z "$RESULTS_FILE" ]; then
                RESULTS_FILE=$(echo "$found" | head -1)
            fi
        fi

        # Look for Summary files
        summary=$(find "$dir" -maxdepth 2 -type f \( \
            -name "Summary*.csv" -o \
            -name "Summary*.txt" \
        \) -newer /tmp/task_start_time 2>/dev/null | head -1)

        if [ -n "$summary" ]; then
            SUMMARY_FILE="$summary"
            echo "Found summary: $SUMMARY_FILE"
        fi
    fi
done

# ============================================================
# Try to save Results from Fiji if window is open
# ============================================================
if [ "$RESULTS_WINDOW" = "true" ] && [ -z "$RESULTS_FILE" ]; then
    echo "Attempting to export Results table..."

    # Create a macro to save results
    SAVE_MACRO="/tmp/save_results.ijm"
    cat > "$SAVE_MACRO" << 'MACROEOF'
if (isOpen("Results")) {
    selectWindow("Results");
    saveAs("Results", "/tmp/Results.csv");
}
if (isOpen("Summary")) {
    selectWindow("Summary");
    saveAs("Results", "/tmp/Summary.csv");
}
MACROEOF

    # Try to run the macro
    FIJI_PATH=$(find_fiji_executable 2>/dev/null)
    if [ -n "$FIJI_PATH" ] && [ -x "$FIJI_PATH" ]; then
        DISPLAY=:1 "$FIJI_PATH" -macro "$SAVE_MACRO" > /tmp/save_results.log 2>&1 &
        sleep 3
    fi

    if [ -f "/tmp/Results.csv" ]; then
        RESULTS_FILE="/tmp/Results.csv"
        echo "Results saved to $RESULTS_FILE"
    fi

    if [ -f "/tmp/Summary.csv" ] && [ -z "$SUMMARY_FILE" ]; then
        SUMMARY_FILE="/tmp/Summary.csv"
        echo "Summary saved to $SUMMARY_FILE"
    fi
fi

# ============================================================
# Cleanup: Close Fiji before parsing
# ============================================================
kill_fiji 2>/dev/null || true

# ============================================================
# Write shell variables to a temp file for Python to read
# This avoids HEREDOC variable interpolation issues
# ============================================================
SHELL_VARS_FILE="/tmp/export_shell_vars.json"
cat > "$SHELL_VARS_FILE" << VAREOF
{
    "results_file": "$RESULTS_FILE",
    "summary_file": "$SUMMARY_FILE",
    "results_window": "$RESULTS_WINDOW",
    "summary_window": "$SUMMARY_WINDOW",
    "image_window": "$IMAGE_WINDOW",
    "image_name": "$IMAGE_NAME",
    "threshold_applied": "$THRESHOLD_APPLIED",
    "final_screenshot": "$FINAL_SCREENSHOT",
    "windows_list": "$(echo "$WINDOWS_LIST" | tr '\n' '|' | sed 's/"/\\"/g')"
}
VAREOF

echo ""
echo "=== Shell variables written to $SHELL_VARS_FILE ==="
cat "$SHELL_VARS_FILE"

# ============================================================
# Run Python script to parse files and create result JSON
# Python reads variables from the temp file, avoiding HEREDOC issues
# ============================================================
echo ""
echo "=== Running Python parser ==="

# Run parser and capture exit code
PARSER_EXIT_CODE=0
python3 /workspace/tasks/count_particles/parse_results.py || PARSER_EXIT_CODE=$?

if [ "$PARSER_EXIT_CODE" -ne 0 ]; then
    echo "ERROR: parse_results.py failed with exit code $PARSER_EXIT_CODE"
    # Create error result JSON
    cat > /tmp/task_result.json << FALLBACK
{
    "particle_count": 0,
    "avg_area": 0,
    "min_area": 0,
    "max_area": 0,
    "total_area": 0,
    "has_measurements": false,
    "results_file_found": false,
    "summary_file_found": false,
    "error": "Python parser failed with exit code $PARSER_EXIT_CODE",
    "windows_list": "$(echo "$WINDOWS_LIST" | tr '\n' '|' | sed 's/"/\\"/g')",
    "timestamp": "$(date -Iseconds)"
}
FALLBACK
    chmod 666 /tmp/task_result.json
    exit 1
fi

# Verify the result was created AND has valid content
if [ -f "/tmp/task_result.json" ]; then
    # Check that particle_count exists and is a number
    if python3 -c "import json; d=json.load(open('/tmp/task_result.json')); assert 'particle_count' in d" 2>/dev/null; then
        echo ""
        echo "=== Verification: task_result.json contents ==="
        cat /tmp/task_result.json
        echo ""
        echo "=== Export Complete ==="
    else
        echo "ERROR: task_result.json is invalid or missing particle_count"
        exit 1
    fi
else
    echo "ERROR: Failed to create /tmp/task_result.json"
    # Create a minimal fallback result
    cat > /tmp/task_result.json << FALLBACK
{
    "particle_count": 0,
    "avg_area": 0,
    "min_area": 0,
    "max_area": 0,
    "total_area": 0,
    "has_measurements": false,
    "results_file_found": false,
    "summary_file_found": false,
    "error": "Python parser failed to create output file",
    "windows_list": "$(echo "$WINDOWS_LIST" | tr '\n' '|' | sed 's/"/\\"/g')",
    "timestamp": "$(date -Iseconds)"
}
FALLBACK
    chmod 666 /tmp/task_result.json
    exit 1
fi
