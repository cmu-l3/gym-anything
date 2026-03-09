#!/bin/bash
# Export script for depth_coded_projection task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Results ==="

# 1. Take final screenshot (Visual Evidence)
take_screenshot /tmp/task_final.png

# 2. Check Output File
OUTPUT_PATH="/home/ga/ImageJ_Data/results/depth_coded_fly_brain.png"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
GT_PATH="/var/lib/imagej/ground_truth/fly_brain_mip.tif"

EXISTS="false"
FILE_SIZE=0
IS_NEW="false"

if [ -f "$OUTPUT_PATH" ]; then
    EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        IS_NEW="true"
    fi
fi

# 3. Create Result JSON
cat > /tmp/depth_coded_result.json << EOF
{
    "output_exists": $EXISTS,
    "output_path": "$OUTPUT_PATH",
    "output_size": $FILE_SIZE,
    "created_during_task": $IS_NEW,
    "gt_available": $([ -f "$GT_PATH" ] && echo "true" || echo "false"),
    "gt_path": "$GT_PATH",
    "timestamp": "$(date +%s)"
}
EOF

# 4. Prepare files for verification (copy to /tmp where verifier can see them easier if needed, 
#    though verifier usually pulls from absolute paths via copy_from_env)
#    We will rely on absolute paths in verifier.

echo "Result exported to /tmp/depth_coded_result.json"
cat /tmp/depth_coded_result.json