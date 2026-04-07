#!/bin/bash
echo "=== Exporting cytc_gor_secondary_structure results ==="

TASK_START=$(cat /tmp/task_start_ts 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/UGENE_Data/results/cytc_structure"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# Helper function to get base64 encoded file content or empty string
get_b64_content() {
    if [ -f "$1" ]; then
        cat "$1" 2>/dev/null | base64 -w 0
    else
        echo ""
    fi
}

# Helper function to check if file was created/modified during task
check_mtime() {
    if [ -f "$1" ]; then
        MTIME=$(stat -c %Y "$1" 2>/dev/null || echo "0")
        if [ "$MTIME" -ge "$TASK_START" ]; then
            echo "true"
        else
            echo "false"
        fi
    else
        echo "false"
    fi
}

# 1. Human FASTA
HUMAN_FASTA="${RESULTS_DIR}/human_cytc.fasta"
HUMAN_EXISTS="false"
[ -f "$HUMAN_FASTA" ] && HUMAN_EXISTS="true"
HUMAN_CREATED=$(check_mtime "$HUMAN_FASTA")
HUMAN_B64=$(get_b64_content "$HUMAN_FASTA")

# 2. GFF Annotations
GFF_FILE="${RESULTS_DIR}/cytc_secondary_structure.gff"
GFF_EXISTS="false"
[ -f "$GFF_FILE" ] && GFF_EXISTS="true"
GFF_CREATED=$(check_mtime "$GFF_FILE")
GFF_B64=$(get_b64_content "$GFF_FILE")

# 3. Longest Helix FASTA
HELIX_FASTA="${RESULTS_DIR}/longest_helix.fasta"
HELIX_EXISTS="false"
[ -f "$HELIX_FASTA" ] && HELIX_EXISTS="true"
HELIX_CREATED=$(check_mtime "$HELIX_FASTA")
HELIX_B64=$(get_b64_content "$HELIX_FASTA")

# 4. Summary Report
REPORT_FILE="${RESULTS_DIR}/structure_summary.txt"
REPORT_EXISTS="false"
[ -f "$REPORT_FILE" ] && REPORT_EXISTS="true"
REPORT_CREATED=$(check_mtime "$REPORT_FILE")
REPORT_B64=$(get_b64_content "$REPORT_FILE")

# Write to JSON using Python to ensure valid formatting
python3 << PYEOF
import json

result = {
    "task_start_ts": int("${TASK_START}" or "0"),
    "human_fasta": {
        "exists": "${HUMAN_EXISTS}" == "true",
        "created_during_task": "${HUMAN_CREATED}" == "true",
        "content_b64": "${HUMAN_B64}"
    },
    "gff_file": {
        "exists": "${GFF_EXISTS}" == "true",
        "created_during_task": "${GFF_CREATED}" == "true",
        "content_b64": "${GFF_B64}"
    },
    "helix_fasta": {
        "exists": "${HELIX_EXISTS}" == "true",
        "created_during_task": "${HELIX_CREATED}" == "true",
        "content_b64": "${HELIX_B64}"
    },
    "report_file": {
        "exists": "${REPORT_EXISTS}" == "true",
        "created_during_task": "${REPORT_CREATED}" == "true",
        "content_b64": "${REPORT_B64}"
    }
}

with open("/tmp/cytc_gor_result.json", "w") as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/cytc_gor_result.json 2>/dev/null || sudo chmod 666 /tmp/cytc_gor_result.json

echo "=== Export complete ==="