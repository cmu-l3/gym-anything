#!/bin/bash
echo "=== Exporting Task Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Helper function to get file stats
get_file_stats() {
    local file_path="$1"
    if [ -f "$file_path" ]; then
        local mtime=$(stat -c %Y "$file_path" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$file_path" 2>/dev/null || echo "0")
        local created_during_task="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during_task="true"
        fi
        echo "{\"exists\": true, \"size_bytes\": $size, \"created_during_task\": $created_during_task}"
    else
        echo "{\"exists\": false, \"size_bytes\": 0, \"created_during_task\": false}"
    fi
}

# Check all required outputs
SCRIPT_STATS=$(get_file_stats "/home/ga/rotate_waveforms.py")
PLOT_STATS=$(get_file_stats "/home/ga/rotation_plot.png")
BAZ_STATS=$(get_file_stats "/home/ga/baz_toli.txt")

# Read BAZ value if file exists
BAZ_VALUE="null"
if [ -f "/home/ga/baz_toli.txt" ]; then
    # Extract the first valid number from the file
    EXTRACTED_VAL=$(grep -oE -- '-?[0-9]+(\.[0-9]+)?' "/home/ga/baz_toli.txt" | head -n 1)
    if [ -n "$EXTRACTED_VAL" ]; then
        BAZ_VALUE=$EXTRACTED_VAL
    fi
    
    # Copy for verifier
    cp /home/ga/baz_toli.txt /tmp/baz_toli.txt 2>/dev/null || true
fi

# Copy script for verifier to inspect
if [ -f "/home/ga/rotate_waveforms.py" ]; then
    cp /home/ga/rotate_waveforms.py /tmp/rotate_waveforms.py 2>/dev/null || true
fi

# Construct JSON output securely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "script_file": $SCRIPT_STATS,
    "plot_file": $PLOT_STATS,
    "baz_file": $BAZ_STATS,
    "reported_baz": $BAZ_VALUE
}
EOF

# Move JSON to accessible path
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results recorded successfully in /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="