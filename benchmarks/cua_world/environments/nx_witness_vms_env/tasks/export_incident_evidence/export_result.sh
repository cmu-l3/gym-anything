#!/bin/bash
echo "=== Exporting Task Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CASE_ID=$(cat /tmp/expected_case_id.txt 2>/dev/null || echo "0")
EXPECTED_START=$(cat /tmp/expected_start_ms.txt 2>/dev/null || echo "0")
EXPECTED_END=$(cat /tmp/expected_end_ms.txt 2>/dev/null || echo "0")
EXPECTED_DURATION_SEC=$(( (EXPECTED_END - EXPECTED_START) / 1000 ))

# Paths
VIDEO_PATH="/home/ga/evidence/case_${CASE_ID}.mkv"
HASH_PATH="/home/ga/evidence/case_${CASE_ID}.mkv.sha256"

# 1. Analyze Video File
# ---------------------
VIDEO_EXISTS="false"
VIDEO_SIZE=0
VIDEO_DURATION=0
VIDEO_RES_W=0
VIDEO_RES_H=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$VIDEO_PATH" ]; then
    VIDEO_EXISTS="true"
    VIDEO_SIZE=$(stat -c %s "$VIDEO_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$VIDEO_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Use ffprobe to get duration and resolution
    if command -v ffprobe > /dev/null; then
        PROBE_JSON=$(ffprobe -v quiet -print_format json -show_format -show_streams "$VIDEO_PATH")
        
        # Extract duration (float)
        VIDEO_DURATION=$(echo "$PROBE_JSON" | python3 -c "import sys, json; d = json.load(sys.stdin); print(d.get('format', {}).get('duration', 0))" 2>/dev/null || echo "0")
        
        # Extract resolution (width)
        VIDEO_RES_W=$(echo "$PROBE_JSON" | python3 -c "import sys, json; d = json.load(sys.stdin); streams = d.get('streams', []); print(streams[0].get('width', 0) if streams else 0)" 2>/dev/null || echo "0")
        VIDEO_RES_H=$(echo "$PROBE_JSON" | python3 -c "import sys, json; d = json.load(sys.stdin); streams = d.get('streams', []); print(streams[0].get('height', 0) if streams else 0)" 2>/dev/null || echo "0")
    fi
    
    # Calculate ACTUAL hash for verification
    ACTUAL_HASH=$(sha256sum "$VIDEO_PATH" | awk '{print $1}')
else
    ACTUAL_HASH=""
fi

# 2. Analyze Hash File
# --------------------
HASH_EXISTS="false"
AGENT_HASH=""

if [ -f "$HASH_PATH" ]; then
    HASH_EXISTS="true"
    # Extract just the hash string (agent might put "hash filename" or just "hash")
    AGENT_HASH_CONTENT=$(cat "$HASH_PATH")
    # Grab the first word which is typically the hash
    AGENT_HASH=$(echo "$AGENT_HASH_CONTENT" | awk '{print $1}')
fi

# 3. Take Screenshot
# ------------------
take_screenshot /tmp/task_final.png

# 4. Generate Result JSON
# -----------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "case_id": "$CASE_ID",
    "expected_duration_sec": $EXPECTED_DURATION_SEC,
    "video_file": {
        "exists": $VIDEO_EXISTS,
        "created_during_task": $FILE_CREATED_DURING_TASK,
        "size_bytes": $VIDEO_SIZE,
        "duration_sec": $VIDEO_DURATION,
        "width": $VIDEO_RES_W,
        "height": $VIDEO_RES_H,
        "actual_sha256": "$ACTUAL_HASH"
    },
    "hash_file": {
        "exists": $HASH_EXISTS,
        "content_hash": "$AGENT_HASH"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json