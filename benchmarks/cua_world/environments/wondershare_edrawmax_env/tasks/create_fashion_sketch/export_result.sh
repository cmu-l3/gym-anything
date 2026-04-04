#!/bin/bash
echo "=== Exporting create_fashion_sketch results ==="

source /workspace/scripts/task_utils.sh

# 1. timestamp checks
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Check output files
EDDX_PATH="/home/ga/Documents/uniform_spec.eddx"
PNG_PATH="/home/ga/Documents/uniform_spec.png"

# Helper to check file status
check_file() {
    local fpath="$1"
    local exists="false"
    local size="0"
    local created_during="false"
    
    if [ -f "$fpath" ]; then
        exists="true"
        size=$(stat -c %s "$fpath" 2>/dev/null || echo "0")
        mtime=$(stat -c %Y "$fpath" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during="true"
        fi
    fi
    echo "{\"exists\": $exists, \"size\": $size, \"created_during\": $created_during}"
}

EDDX_STATS=$(check_file "$EDDX_PATH")
PNG_STATS=$(check_file "$PNG_PATH")

# 3. Final screenshot
take_screenshot /tmp/task_final.png

# 4. Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "eddx_file": $EDDX_STATS,
    "png_file": $PNG_STATS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Set permissions for the verifier to read it
chmod 644 /tmp/task_result.json 2>/dev/null || true
chmod 644 "$EDDX_PATH" 2>/dev/null || true
chmod 644 "$PNG_PATH" 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"