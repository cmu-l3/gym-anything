#!/bin/bash
echo "=== Exporting sars2_ngs_read_mapping results ==="

RESULTS_DIR="/home/ga/UGENE_Data/ngs/results"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check alignment.bam
BAM_FILE="${RESULTS_DIR}/alignment.bam"
BAM_EXISTS="false"
BAM_VALID="false"
BAM_SIZE=0

if [ -f "$BAM_FILE" ]; then
    BAM_EXISTS="true"
    BAM_SIZE=$(stat -c %s "$BAM_FILE" 2>/dev/null || echo "0")
    
    # Check for BGZF/BAM magic bytes (1f 8b 08)
    MAGIC=$(xxd -l 3 -p "$BAM_FILE" 2>/dev/null || echo "")
    if [ "$MAGIC" = "1f8b08" ]; then
        BAM_VALID="true"
    fi
fi

# 3. Check patient_consensus.fasta
FASTA_FILE="${RESULTS_DIR}/patient_consensus.fasta"
FASTA_EXISTS="false"
FASTA_VALID="false"
CONSENSUS_LENGTH=0
BASE_1841=""

if [ -f "$FASTA_FILE" ]; then
    FASTA_EXISTS="true"
    
    if head -n 1 "$FASTA_FILE" | grep -q "^>"; then
        FASTA_VALID="true"
    fi
    
    # Strip headers and newlines to get pure sequence string
    SEQ_STRING=$(grep -v "^>" "$FASTA_FILE" | tr -d '\n\r' 2>/dev/null)
    CONSENSUS_LENGTH=${#SEQ_STRING}
    
    # Extract the base at the mutation coordinate (1-based index 1841)
    if [ "$CONSENSUS_LENGTH" -ge 1841 ]; then
        BASE_1841=$(echo "$SEQ_STRING" | cut -c 1841)
    fi
fi

# 4. Check mapping_report.txt
REPORT_FILE="${RESULTS_DIR}/mapping_report.txt"
REPORT_EXISTS="false"
REPORT_MENTIONS_UGENE="false"
REPORT_MENTIONS_SUCCESS="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE" 2>/dev/null | tr '\n' ' ' | head -c 500)
    
    if echo "$REPORT_CONTENT" | grep -qi "ugene"; then
        REPORT_MENTIONS_UGENE="true"
    fi
    if echo "$REPORT_CONTENT" | grep -qi "success\|complete\|mapped"; then
        REPORT_MENTIONS_SUCCESS="true"
    fi
fi

# 5. Build JSON output using python
cat << PYEOF > /tmp/build_json.py
import json

result = {
    "bam_exists": "$BAM_EXISTS" == "true",
    "bam_valid": "$BAM_VALID" == "true",
    "bam_size_bytes": int("$BAM_SIZE"),
    "fasta_exists": "$FASTA_EXISTS" == "true",
    "fasta_valid": "$FASTA_VALID" == "true",
    "consensus_length": int("$CONSENSUS_LENGTH"),
    "base_1841": "$BASE_1841",
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_mentions_ugene": "$REPORT_MENTIONS_UGENE" == "true",
    "report_mentions_success": "$REPORT_MENTIONS_SUCCESS" == "true"
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

python3 /tmp/build_json.py
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export completed. Results saved to /tmp/task_result.json."
cat /tmp/task_result.json