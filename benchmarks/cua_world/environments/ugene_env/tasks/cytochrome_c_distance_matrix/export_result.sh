#!/bin/bash
echo "=== Exporting cytochrome_c_distance_matrix results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/UGENE_Data/results"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# Check Alignment File (.sto)
STO_FILE="${RESULTS_DIR}/cytc_alignment.sto"
STO_EXISTS=false
STO_VALID=false
STO_SEQ_COUNT=0
STO_MTIME=0

if [ -f "$STO_FILE" ]; then
    STO_EXISTS=true
    STO_MTIME=$(stat -c %Y "$STO_FILE" 2>/dev/null || echo "0")
    if head -n 5 "$STO_FILE" | grep -q "STOCKHOLM"; then
        STO_VALID=true
    fi
    # Count unique sequence identifiers (lines that don't start with # or //, and have data)
    STO_SEQ_COUNT=$(grep -v "^#" "$STO_FILE" | grep -v "^//" | awk '{print $1}' | grep -v "^$" | sort -u | wc -l)
fi

# Check Distance Matrix (.csv or .txt or .tsv)
MATRIX_FILE="${RESULTS_DIR}/cytc_distance_matrix.csv"
MATRIX_EXISTS=false
MATRIX_HAS_LABELS=false
MATRIX_ROWS=0
MATRIX_MTIME=0

if [ ! -f "$MATRIX_FILE" ]; then
    # Look for other extensions just in case agent used .tsv or .txt
    ALT_MATRIX=$(ls "${RESULTS_DIR}"/cytc_distance_matrix.* 2>/dev/null | head -1)
    if [ -n "$ALT_MATRIX" ]; then
        MATRIX_FILE="$ALT_MATRIX"
    fi
fi

if [ -f "$MATRIX_FILE" ]; then
    MATRIX_EXISTS=true
    MATRIX_MTIME=$(stat -c %Y "$MATRIX_FILE" 2>/dev/null || echo "0")
    MATRIX_ROWS=$(wc -l < "$MATRIX_FILE" 2>/dev/null || echo "0")
    # Check if any species labels exist (Human, P99999, Chicken, etc.)
    if grep -qi "Human\|P99999\|Chicken\|P67881\|Neurospora\|P00048\|Cannabis\|P00053\|Yeast\|P00044\|Drosophila\|P04657\|Horse\|P00004\|Pig\|P62895" "$MATRIX_FILE"; then
        MATRIX_HAS_LABELS=true
    fi
fi

# Check Analysis Report (.txt)
REPORT_FILE="${RESULTS_DIR}/cytc_analysis_report.txt"
REPORT_EXISTS=false
REPORT_MTIME=0
REPORT_HAS_HUMAN=false
REPORT_HAS_PERCENT=false
REPORT_MENTIONS_HORSE_PIG=false
REPORT_MENTIONS_FUNGI=false
REPORT_CONTENT_LENGTH=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS=true
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_CONTENT_LENGTH=$(wc -c < "$REPORT_FILE" 2>/dev/null || echo "0")
    
    if grep -qi "Human\|P99999" "$REPORT_FILE"; then
        REPORT_HAS_HUMAN=true
    fi
    
    if grep -q "%\|percent" "$REPORT_FILE"; then
        REPORT_HAS_PERCENT=true
    fi
    
    if grep -qi "Horse\|P00004\|Pig\|P62895\|Mammal" "$REPORT_FILE"; then
        REPORT_MENTIONS_HORSE_PIG=true
    fi
    
    if grep -qi "Neurospora\|P00048\|Yeast\|P00044\|Fungi\|Saccharomyces" "$REPORT_FILE"; then
        REPORT_MENTIONS_FUNGI=true
    fi
fi

# Write JSON
python3 << PYEOF
import json
result = {
    "task_start_time": int("${TASK_START}" or "0"),
    "sto_exists": "${STO_EXISTS}" == "true",
    "sto_valid": "${STO_VALID}" == "true",
    "sto_seq_count": int("${STO_SEQ_COUNT}" or "0"),
    "sto_mtime": int("${STO_MTIME}" or "0"),
    "matrix_exists": "${MATRIX_EXISTS}" == "true",
    "matrix_has_labels": "${MATRIX_HAS_LABELS}" == "true",
    "matrix_rows": int("${MATRIX_ROWS}" or "0"),
    "matrix_mtime": int("${MATRIX_MTIME}" or "0"),
    "report_exists": "${REPORT_EXISTS}" == "true",
    "report_mtime": int("${REPORT_MTIME}" or "0"),
    "report_content_length": int("${REPORT_CONTENT_LENGTH}" or "0"),
    "report_has_human": "${REPORT_HAS_HUMAN}" == "true",
    "report_has_percent": "${REPORT_HAS_PERCENT}" == "true",
    "report_mentions_horse_pig": "${REPORT_MENTIONS_HORSE_PIG}" == "true",
    "report_mentions_fungi": "${REPORT_MENTIONS_FUNGI}" == "true"
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json
echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="