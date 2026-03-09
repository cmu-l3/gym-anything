#!/bin/bash
echo "=== Exporting FFT Analysis Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/Fiji_Data/results/fft_analysis"
OUTPUT_JSON="/tmp/task_result.json"

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check Output Files
FFT_IMG="$RESULTS_DIR/fft_power_spectrum.png"
FILTERED_IMG="$RESULTS_DIR/bandpass_filtered.png"
PROFILE_CSV="$RESULTS_DIR/line_profile.csv"
REPORT_TXT="$RESULTS_DIR/spacing_report.txt"

# Helper to check file status
check_file() {
    local fpath=$1
    if [ -f "$fpath" ]; then
        local fsize=$(stat -c%s "$fpath")
        local fmtime=$(stat -c%Y "$fpath")
        local created_during="false"
        if [ "$fmtime" -gt "$TASK_START" ]; then created_during="true"; fi
        echo "{\"exists\": true, \"size\": $fsize, \"created_during_task\": $created_during}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

# 3. Extract reported spacing value from text report
REPORTED_VAL="null"
if [ -f "$REPORT_TXT" ]; then
    # Look for a number followed by u, um, µ, micron
    # Regex: find digits (float) followed optionally by space then unit
    REPORTED_VAL=$(grep -oP '\d+(\.\d+)?\s*(u|µ|um|micron)' "$REPORT_TXT" | head -1 | grep -oP '\d+(\.\d+)?' || echo "null")
    if [ -z "$REPORTED_VAL" ]; then REPORTED_VAL="null"; fi
fi

# 4. Generate JSON result
cat > "$OUTPUT_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "files": {
        "fft_image": $(check_file "$FFT_IMG"),
        "filtered_image": $(check_file "$FILTERED_IMG"),
        "line_profile": $(check_file "$PROFILE_CSV"),
        "report": $(check_file "$REPORT_TXT")
    },
    "extracted_spacing_um": $REPORTED_VAL,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 "$OUTPUT_JSON"
echo "Result exported to $OUTPUT_JSON"
cat "$OUTPUT_JSON"