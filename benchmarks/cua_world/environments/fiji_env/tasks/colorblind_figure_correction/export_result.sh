#!/bin/bash
echo "=== Exporting Colorblind Figure Correction results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

ACCESSIBLE_PATH="/home/ga/Fiji_Data/results/figures/accessible_composite.png"
PROOF_PATH="/home/ga/Fiji_Data/results/figures/deuteranopia_proof.png"

# Check output existence and timestamps
ACC_EXISTS="false"
ACC_MTIME=0
if [ -f "$ACCESSIBLE_PATH" ]; then
    ACC_EXISTS="true"
    ACC_MTIME=$(stat -c %Y "$ACCESSIBLE_PATH" 2>/dev/null || echo "0")
fi

PROOF_EXISTS="false"
PROOF_MTIME=0
if [ -f "$PROOF_PATH" ]; then
    PROOF_EXISTS="true"
    PROOF_MTIME=$(stat -c %Y "$PROOF_PATH" 2>/dev/null || echo "0")
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "accessible_exists": $ACC_EXISTS,
    "accessible_mtime": $ACC_MTIME,
    "proof_exists": $PROOF_EXISTS,
    "proof_mtime": $PROOF_MTIME,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"