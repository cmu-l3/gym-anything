#!/bin/bash
set -e

echo "=== Exporting PEBL BIDS Standardization Result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Package the BIDS directory into a tarball for robust Python verification on host
BIDS_DIR="/home/ga/pebl/bids_dataset"
TAR_PATH="/tmp/bids_dataset.tar.gz"

if [ -d "$BIDS_DIR" ]; then
    BIDS_EXISTS="true"
    # Ensure all files in BIDS dir are readable
    chmod -R 755 "$BIDS_DIR" 2>/dev/null || true
    tar -czf "$TAR_PATH" -C /home/ga/pebl bids_dataset 2>/dev/null || true
else
    BIDS_EXISTS="false"
fi

# Prepare result JSON with metadata and ground truth
GT_IDS=$(cat /tmp/ground_truth_ids.json 2>/dev/null || echo "[]")

TEMP_JSON=$(mktemp /tmp/bids_result.XXXXXX.json)
cat << EOF > "$TEMP_JSON"
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "bids_dir_exists": $BIDS_EXISTS,
    "tarball_exists": $([ -f "$TAR_PATH" ] && echo "true" || echo "false"),
    "ground_truth_ids": $GT_IDS
}
EOF

# Make sure files are readable by verifier
chmod 666 "$TEMP_JSON"
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
[ -f "$TAR_PATH" ] && chmod 666 "$TAR_PATH"

# Final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/bids_final_screenshot.png 2>/dev/null || true

echo "Result JSON saved to /tmp/task_result.json"
echo "BIDS Tarball saved to $TAR_PATH"
echo "=== Export Complete ==="