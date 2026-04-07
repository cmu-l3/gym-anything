#!/bin/bash
echo "=== Exporting broadcast_watermark_composite result ==="

# Paths
OUTPUT_DIR="/home/ga/OpenToonz/output/watermark_test"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_JSON="/tmp/task_result.json"
VERIFICATION_FRAME="/tmp/verification_frame.png"

# 1. Take Final Screenshot (for VLM context)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Analyze Output Files
FILE_COUNT=0
FILES_NEWER="false"
TOTAL_SIZE=0

if [ -d "$OUTPUT_DIR" ]; then
    # Count PNGs
    FILE_COUNT=$(find "$OUTPUT_DIR" -name "*.png" | wc -l)
    
    # Check timestamps
    NEWER_COUNT=$(find "$OUTPUT_DIR" -name "*.png" -newer /tmp/task_start_time.txt | wc -l)
    if [ "$NEWER_COUNT" -gt 0 ]; then
        FILES_NEWER="true"
    fi
    
    # Check total size
    TOTAL_SIZE=$(du -sb "$OUTPUT_DIR" | cut -f1 2>/dev/null || echo "0")
fi

# 3. Select a representative frame for verification
# We pick the middle frame to ensure the watermark persists through the animation
FRAME_TO_CHECK=""
if [ "$FILE_COUNT" -gt 0 ]; then
    # Sort files and pick middle one
    FRAME_TO_CHECK=$(find "$OUTPUT_DIR" -name "*.png" | sort | awk "NR==$((FILE_COUNT/2 + 1))")
    
    if [ -f "$FRAME_TO_CHECK" ]; then
        cp "$FRAME_TO_CHECK" "$VERIFICATION_FRAME"
        echo "Selected verification frame: $FRAME_TO_CHECK"
    fi
fi

# 4. Check if frame exists for export
FRAME_EXISTS="false"
if [ -f "$VERIFICATION_FRAME" ]; then
    FRAME_EXISTS="true"
fi

# 5. Create Result JSON
cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_count": $FILE_COUNT,
    "files_created_during_task": $FILES_NEWER,
    "total_size_bytes": $TOTAL_SIZE,
    "verification_frame_exists": $FRAME_EXISTS,
    "verification_frame_path": "$VERIFICATION_FRAME"
}
EOF

# Set permissions for copy_from_env
chmod 644 "$RESULT_JSON" 2>/dev/null || true
if [ -f "$VERIFICATION_FRAME" ]; then
    chmod 644 "$VERIFICATION_FRAME"
fi

echo "Export complete. Result:"
cat "$RESULT_JSON"