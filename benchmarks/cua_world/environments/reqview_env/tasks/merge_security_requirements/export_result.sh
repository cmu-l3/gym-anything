#!/bin/bash
echo "=== Exporting merge_security_requirements result ==="

# Record end time and take evidence screenshot
date +%s > /tmp/task_end_time.txt
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Determine project path (reconstructing logic from setup)
PROJECT_PATH="/home/ga/Documents/ReqView/merge_security_project"

# Check if ASVS file still exists on disk
# Note: ReqView might delete the file or just remove the reference from project.json
ASVS_FILE_EXISTS="false"
if [ -f "$PROJECT_PATH/documents/ASVS.json" ]; then
    ASVS_FILE_EXISTS="true"
fi

# Check if SRS file was modified
SRS_MODIFIED="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
SRS_MTIME=$(stat -c %Y "$PROJECT_PATH/documents/SRS.json" 2>/dev/null || echo "0")
if [ "$SRS_MTIME" -gt "$TASK_START" ]; then
    SRS_MODIFIED="true"
fi

# Create simple result JSON for debug (verifier does heavy lifting via file inspection)
cat > /tmp/task_result.json << EOF
{
    "asvs_file_exists": $ASVS_FILE_EXISTS,
    "srs_modified": $SRS_MODIFIED,
    "project_path": "$PROJECT_PATH",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result summary:"
cat /tmp/task_result.json
echo "=== Export complete ==="