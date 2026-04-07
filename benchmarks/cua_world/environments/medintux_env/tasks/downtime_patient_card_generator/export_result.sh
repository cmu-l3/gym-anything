#!/bin/bash
echo "=== Exporting Downtime Patient Card Generator results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/downtime_cards"
GROUND_TRUTH="/var/lib/medintux/downtime_ground_truth.json"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare result staging area
mkdir -p /tmp/verification_data
rm -rf /tmp/verification_data/*

# 1. Copy Ground Truth
if [ -f "$GROUND_TRUTH" ]; then
    cp "$GROUND_TRUTH" /tmp/verification_data/ground_truth.json
fi

# 2. Copy Generated Files
FILES_GENERATED=0
if [ -d "$OUTPUT_DIR" ]; then
    # Copy html files for verification
    cp "$OUTPUT_DIR"/*.html /tmp/verification_data/ 2>/dev/null || true
    FILES_GENERATED=$(ls "$OUTPUT_DIR"/*.html 2>/dev/null | wc -l)
    
    # Check timestamps (anti-gaming)
    NEWEST_FILE=$(ls -t "$OUTPUT_DIR"/*.html 2>/dev/null | head -1)
    if [ -n "$NEWEST_FILE" ]; then
        FILE_MTIME=$(stat -c %Y "$NEWEST_FILE")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
             CREATED_DURING_TASK="true"
        else
             CREATED_DURING_TASK="false"
        fi
    else
        CREATED_DURING_TASK="false"
    fi
else
    CREATED_DURING_TASK="false"
fi

# 3. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "files_generated_count": $FILES_GENERATED,
    "created_during_task": $CREATED_DURING_TASK,
    "output_dir_exists": $([ -d "$OUTPUT_DIR" ] && echo "true" || echo "false"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Package verification data into a tarball for easy copy_from_env
# (We put the result json and the html files together)
cd /tmp/verification_data
cp /tmp/task_result.json .
tar -czf /tmp/verification_package.tar.gz .

# Ensure permissions
chmod 666 /tmp/task_result.json
chmod 666 /tmp/verification_package.tar.gz

echo "Export complete. Package at /tmp/verification_package.tar.gz"