#!/bin/bash
echo "=== Exporting HTPC task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare export directory for task results
rm -f /tmp/exported_vlcrc /tmp/exported_htpc_proof.png /tmp/exported_htpc_config.json

# Export the VLC configuration file (vlcrc)
if [ -f "/home/ga/.config/vlc/vlcrc" ]; then
    cp /home/ga/.config/vlc/vlcrc /tmp/exported_vlcrc
    chmod 666 /tmp/exported_vlcrc
    VLCRC_EXISTS=true
else
    VLCRC_EXISTS=false
fi

# Export the visual proof screenshot
PROOF_PATH="/home/ga/Pictures/vlc/htpc_proof.png"
if [ -f "$PROOF_PATH" ]; then
    cp "$PROOF_PATH" /tmp/exported_htpc_proof.png
    chmod 666 /tmp/exported_htpc_proof.png
    PROOF_EXISTS=true
    
    # Check if created during task
    PROOF_MTIME=$(stat -c %Y "$PROOF_PATH" 2>/dev/null || echo "0")
    if [ "$PROOF_MTIME" -gt "$TASK_START" ]; then
        PROOF_CREATED_DURING_TASK=true
    else
        PROOF_CREATED_DURING_TASK=false
    fi
else
    PROOF_EXISTS=false
    PROOF_CREATED_DURING_TASK=false
fi

# Export the JSON manifest
MANIFEST_PATH="/home/ga/Documents/htpc_config.json"
if [ -f "$MANIFEST_PATH" ]; then
    cp "$MANIFEST_PATH" /tmp/exported_htpc_config.json
    chmod 666 /tmp/exported_htpc_config.json
    MANIFEST_EXISTS=true
else
    MANIFEST_EXISTS=false
fi

# Create a master JSON result file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "vlcrc_exists": $VLCRC_EXISTS,
    "proof_exists": $PROOF_EXISTS,
    "proof_created_during_task": $PROOF_CREATED_DURING_TASK,
    "manifest_exists": $MANIFEST_EXISTS
}
EOF

# Move to final location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="