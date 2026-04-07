#!/bin/bash
echo "=== Exporting Visual Echo Results ==="

# Paths
OUTPUT_DIR="/home/ga/OpenToonz/output/echo_effect"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot (Evidence of UI state)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Analyze Output Files
echo "Analyzing output files in $OUTPUT_DIR..."

# Count PNG files
FILE_COUNT=$(find "$OUTPUT_DIR" -name "*.png" -type f | wc -l)

# Check timestamps (Anti-gaming: must be created AFTER task start)
NEW_FILES_COUNT=$(find "$OUTPUT_DIR" -name "*.png" -type f -newer /tmp/task_start_time.txt | wc -l)

# Select a representative frame for VLM verification (e.g., frame 10, where overlap should occur)
# We sort to find the ~10th frame
SAMPLE_FRAME=$(find "$OUTPUT_DIR" -name "*.png" | sort | sed -n '10p')

# If frame 10 doesn't exist (short render), take the last one
if [ -z "$SAMPLE_FRAME" ]; then
    SAMPLE_FRAME=$(find "$OUTPUT_DIR" -name "*.png" | sort | tail -1)
fi

SAMPLE_FRAME_EXISTS="false"
SAMPLE_FRAME_PATH=""

if [ -n "$SAMPLE_FRAME" ] && [ -f "$SAMPLE_FRAME" ]; then
    SAMPLE_FRAME_EXISTS="true"
    SAMPLE_FRAME_PATH="$SAMPLE_FRAME"
    # Copy to /tmp for easier extraction if needed
    cp "$SAMPLE_FRAME" /tmp/sample_frame.png
fi

# 3. JSON Export
# We use Python to write JSON to ensure proper formatting
python3 -c "
import json
import os

result = {
    'task_start': $TASK_START,
    'file_count': $FILE_COUNT,
    'new_files_count': $NEW_FILES_COUNT,
    'sample_frame_exists': $SAMPLE_FRAME_EXISTS,
    'sample_frame_path': '/tmp/sample_frame.png' if '$SAMPLE_FRAME_EXISTS' == 'true' else ''
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# 4. Cleanup/Permissions
chmod 644 /tmp/task_result.json
chmod 644 /tmp/sample_frame.png 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json