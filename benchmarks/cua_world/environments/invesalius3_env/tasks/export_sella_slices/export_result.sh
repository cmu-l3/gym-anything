#!/bin/bash
set -e

echo "=== Exporting export_sella_slices result ==="

source /workspace/scripts/task_utils.sh

# Record task end info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_DIR="/tmp/task_results"
mkdir -p "$RESULT_DIR"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Helper function to check a file
check_file() {
    local fpath="$1"
    local result_prefix="$2"
    
    if [ -f "$fpath" ]; then
        echo "\"${result_prefix}_exists\": true,"
        
        # Check size
        local fsize=$(stat -c%s "$fpath" 2>/dev/null || echo "0")
        echo "\"${result_prefix}_size\": $fsize,"
        
        # Check timestamp
        local mtime=$(stat -c%Y "$fpath" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "\"${result_prefix}_created_during_task\": true,"
        else
            echo "\"${result_prefix}_created_during_task\": false,"
        fi
        
        # Check PNG magic bytes
        local magic=$(xxd -l 8 -p "$fpath" 2>/dev/null || echo "")
        if [ "$magic" = "89504e470d0a1a0a" ]; then
            echo "\"${result_prefix}_valid_png\": true,"
        else
            echo "\"${result_prefix}_valid_png\": false,"
        fi
        
        # Calculate MD5 for distinctness check
        local hash=$(md5sum "$fpath" | awk '{print $1}')
        echo "\"${result_prefix}_hash\": \"$hash\","
    else
        echo "\"${result_prefix}_exists\": false,"
        echo "\"${result_prefix}_size\": 0,"
        echo "\"${result_prefix}_created_during_task\": false,"
        echo "\"${result_prefix}_valid_png\": false,"
        echo "\"${result_prefix}_hash\": \"none_$result_prefix\","
    fi
}

# Generate JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    $(check_file "/home/ga/Documents/axial_sella.png" "axial")
    $(check_file "/home/ga/Documents/sagittal_sella.png" "sagittal")
    $(check_file "/home/ga/Documents/coronal_sella.png" "coronal")
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Clean up JSON syntax (remove trailing comma from last item)
# This is a hacky but effective way to ensure valid JSON in bash
sed -i '$ s/,$//' /tmp/task_result.json

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="