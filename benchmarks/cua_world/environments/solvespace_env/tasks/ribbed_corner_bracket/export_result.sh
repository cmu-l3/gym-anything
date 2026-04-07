#!/bin/bash
echo "=== Exporting ribbed_corner_bracket task result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Target file paths
OUTPUT_PATH="/home/ga/Documents/SolveSpace/ribbed_bracket.slvs"
STL_PATH="/tmp/ribbed_bracket.stl"

OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
STL_GENERATED="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if the file was saved after the task started
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Attempt to export STL using solvespace-cli for geometric verification
    echo "Attempting to generate STL from the parametric model..."
    if which solvespace-cli >/dev/null; then
        # Export mesh to temp directory
        su - ga -c "solvespace-cli export-mesh $STL_PATH $OUTPUT_PATH" 2>/tmp/export.log || true
        
        if [ -f "$STL_PATH" ]; then
            STL_SIZE=$(stat -c %s "$STL_PATH" 2>/dev/null || echo "0")
            if [ "$STL_SIZE" -gt 100 ]; then
                STL_GENERATED="true"
                echo "STL generated successfully ($STL_SIZE bytes)"
            else
                echo "STL generation resulted in an empty/invalid file."
            fi
        else
            echo "Failed to generate STL. The 2D profile might not be fully closed."
        fi
    else
        echo "solvespace-cli not found in PATH."
    fi
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "solvespace" > /dev/null && echo "true" || echo "false")

# Create JSON result securely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "stl_generated": $STL_GENERATED,
    "app_was_running": $APP_RUNNING
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="