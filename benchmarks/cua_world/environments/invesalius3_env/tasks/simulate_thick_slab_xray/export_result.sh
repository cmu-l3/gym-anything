#!/bin/bash
echo "=== Exporting simulate_thick_slab_xray result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State
take_screenshot /tmp/task_final.png
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. analyze_file Function
analyze_file() {
    local path="$1"
    local name="$2"
    
    if [ -f "$path" ]; then
        EXISTS="true"
        SIZE=$(stat -c %s "$path" 2>/dev/null || echo "0")
        MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        
        # Check if created/modified during task
        if [ "$MTIME" -gt "$TASK_START" ]; then
            CREATED_DURING="true"
        else
            CREATED_DURING="false"
        fi
        
        # Verify PNG Magic Bytes
        MAGIC=$(head -c 8 "$path" | od -t x1 -An | tr -d ' \n')
        if [ "$MAGIC" = "89504e470d0a1a0a" ]; then
            VALID_PNG="true"
        else
            VALID_PNG="false"
        fi
    else
        EXISTS="false"
        SIZE="0"
        MTIME="0"
        CREATED_DURING="false"
        VALID_PNG="false"
    fi
    
    echo "\"$name\": { \"exists\": $EXISTS, \"size\": $SIZE, \"created_during_task\": $CREATED_DURING, \"valid_png\": $VALID_PNG, \"path\": \"$path\" }"
}

# 3. Analyze Output Files
CORONAL_JSON=$(analyze_file "/home/ga/Documents/coronal_thick_slab.png" "coronal")
SAGITTAL_JSON=$(analyze_file "/home/ga/Documents/sagittal_thick_slab.png" "sagittal")

# 4. Generate Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "files": {
        $CORONAL_JSON,
        $SAGITTAL_JSON
    }
}
EOF

# 5. Save and Cleanup
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="