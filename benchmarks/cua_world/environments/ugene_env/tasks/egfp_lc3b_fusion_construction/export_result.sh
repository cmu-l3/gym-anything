#!/bin/bash
echo "=== Exporting task results ==="

RESULTS_DIR="/home/ga/UGENE_Data/fusion_design/results"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final UI state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

DNA_FASTA="${RESULTS_DIR}/egfp_lc3b_fusion.fasta"
PROT_FASTA="${RESULTS_DIR}/egfp_lc3b_protein.fasta"
REPORT_TXT="${RESULTS_DIR}/fusion_report.txt"

DNA_EXISTS=false
PROT_EXISTS=false
REPORT_EXISTS=false

DNA_SEQ=""
PROT_SEQ=""
REPORT_CONTENT=""
DNA_MTIME=0
PROT_MTIME=0
REPORT_MTIME=0

if [ -f "$DNA_FASTA" ]; then
    DNA_EXISTS=true
    DNA_MTIME=$(stat -c %Y "$DNA_FASTA" 2>/dev/null || echo "0")
    # Clean sequence for easy verification
    DNA_SEQ=$(grep -v "^>" "$DNA_FASTA" 2>/dev/null | tr -d '\n\r ' | tr 'a-z' 'A-Z')
fi

if [ -f "$PROT_FASTA" ]; then
    PROT_EXISTS=true
    PROT_MTIME=$(stat -c %Y "$PROT_FASTA" 2>/dev/null || echo "0")
    # Clean sequence for easy verification
    PROT_SEQ=$(grep -v "^>" "$PROT_FASTA" 2>/dev/null | tr -d '\n\r ' | tr 'a-z' 'A-Z')
fi

if [ -f "$REPORT_TXT" ]; then
    REPORT_EXISTS=true
    REPORT_MTIME=$(stat -c %Y "$REPORT_TXT" 2>/dev/null || echo "0")
    REPORT_CONTENT=$(cat "$REPORT_TXT" 2>/dev/null | head -100)
fi

# Package into JSON safely
TEMP_JSON=$(mktemp /tmp/fusion_result.XXXXXX.json)
python3 << PYEOF
import json
import urllib.parse

result = {
    "task_start_ts": int("${TASK_START}" or "0"),
    "dna_exists": "${DNA_EXISTS}" == "true",
    "prot_exists": "${PROT_EXISTS}" == "true",
    "report_exists": "${REPORT_EXISTS}" == "true",
    "dna_mtime": int("${DNA_MTIME}" or "0"),
    "prot_mtime": int("${PROT_MTIME}" or "0"),
    "report_mtime": int("${REPORT_MTIME}" or "0"),
    "dna_seq": "${DNA_SEQ}",
    "prot_seq": "${PROT_SEQ}",
    "report_content": urllib.parse.unquote("$(echo -n "$REPORT_CONTENT" | python3 -c 'import urllib.parse, sys; print(urllib.parse.quote(sys.stdin.read()))')")
}

with open("${TEMP_JSON}", "w") as f:
    json.dump(result, f)
PYEOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="