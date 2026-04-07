#!/bin/bash
echo "=== Exporting SRTT Task Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final visual state
take_screenshot /tmp/task_end.png

# 2. Gather file metadata
EXP_DIR="/home/ga/PsychoPyExperiments"
PSYEXP="$EXP_DIR/srtt_experiment.psyexp"
SEQ_CSV="$EXP_DIR/conditions/srtt_sequence_block.csv"
RND_CSV="$EXP_DIR/conditions/srtt_random_block.csv"
BLK_CSV="$EXP_DIR/conditions/srtt_blocks.csv"

# Function to get file info
get_file_info() {
    local f="$1"
    if [ -f "$f" ]; then
        local size=$(stat -c%s "$f")
        local mtime=$(stat -c%Y "$f")
        echo "{\"exists\": true, \"size\": $size, \"mtime\": $mtime}"
    else
        echo "{\"exists\": false, \"size\": 0, \"mtime\": 0}"
    fi
}

# 3. Create result JSON
# We don't parse content here; the verifier will pull the files and parse them.
# We just provide metadata and the nonce.

TASK_START=$(get_task_start)
NONCE=$(get_nonce)

cat > /tmp/task_result.json <<EOF
{
    "task_start_time": $TASK_START,
    "result_nonce": "$NONCE",
    "timestamp": "$(date -Iseconds)",
    "files": {
        "experiment": $(get_file_info "$PSYEXP"),
        "sequence": $(get_file_info "$SEQ_CSV"),
        "random": $(get_file_info "$RND_CSV"),
        "blocks": $(get_file_info "$BLK_CSV")
    }
}
EOF

# Ensure permissions for copy_from_env
chmod 666 /tmp/task_result.json
chmod 644 /tmp/task_end.png 2>/dev/null || true

echo "Result metadata saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="