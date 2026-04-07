#!/bin/bash
echo "=== Exporting cytochrome_c_heme_motif_search results ==="

# Record task end time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/UGENE_Data/results"

# Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize tracking variables
STO_EXISTS="false"
STO_VALID="false"
STO_SEQ_COUNT=0
GFF_EXISTS="false"
GFF_HAS_MOTIFS="false"
REPORT_EXISTS="false"
REPORT_HAS_CONSERVATION="false"
REPORT_HAS_POSITIONS="false"
FILES_CREATED_DURING_TASK="false"

# 1. Check Stockholm Alignment Export
STO_FILE="${RESULTS_DIR}/cytc_alignment.sto"
if [ -f "$STO_FILE" ] && [ -s "$STO_FILE" ]; then
    STO_EXISTS="true"
    
    # Check timestamp for anti-gaming
    MTIME=$(stat -c %Y "$STO_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILES_CREATED_DURING_TASK="true"
    fi
    
    # Check format
    if head -n 5 "$STO_FILE" | grep -q "STOCKHOLM"; then
        STO_VALID="true"
    fi
    
    # Check sequences presence by parsing Uniprot accessions
    for acc in P99999 P67881 P00048 P00053 P00044 P04657 P00004 P62895; do
        if grep -q "$acc" "$STO_FILE"; then
            STO_SEQ_COUNT=$((STO_SEQ_COUNT+1))
        fi
    done
fi

# 2. Check GFF Motif Export
GFF_FILE="${RESULTS_DIR}/cytc_heme_motifs.gff"
if [ -f "$GFF_FILE" ] && [ -s "$GFF_FILE" ]; then
    GFF_EXISTS="true"
    
    MTIME=$(stat -c %Y "$GFF_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILES_CREATED_DURING_TASK="true"
    fi
    
    # Check for actual annotations (coordinate entries)
    # GFF format contains tab-separated entries with start/end coordinates
    if grep -v "^#" "$GFF_FILE" | grep -qP '\t\d+\t\d+\t'; then
        GFF_HAS_MOTIFS="true"
    fi
fi

# 3. Check Text Summary Report
REPORT_FILE="${RESULTS_DIR}/heme_motif_report.txt"
if [ -f "$REPORT_FILE" ] && [ -s "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    
    MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILES_CREATED_DURING_TASK="true"
    fi
    
    REPORT_CONTENT=$(cat "$REPORT_FILE")
    
    # Mentions motif and conservation
    if echo "$REPORT_CONTENT" | grep -qiP 'CXXCH|C\.\.CH|heme' && echo "$REPORT_CONTENT" | grep -qiP 'conserv|univers|all species'; then
        REPORT_HAS_CONSERVATION="true"
    fi
    
    # Contains positions/coordinates (should have multiple numbers indicating positions)
    NUM_DIGITS=$(echo "$REPORT_CONTENT" | grep -oP '\b\d+\b' | wc -l)
    if [ "$NUM_DIGITS" -ge 4 ]; then
        REPORT_HAS_POSITIONS="true"
    fi
fi

# 4. Construct JSON payload
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "sto_exists": $STO_EXISTS,
    "sto_valid": $STO_VALID,
    "sto_seq_count": $STO_SEQ_COUNT,
    "gff_exists": $GFF_EXISTS,
    "gff_has_motifs": $GFF_HAS_MOTIFS,
    "report_exists": $REPORT_EXISTS,
    "report_mentions_conservation": $REPORT_HAS_CONSERVATION,
    "report_has_positions": $REPORT_HAS_POSITIONS,
    "files_created_during_task": $FILES_CREATED_DURING_TASK
}
EOF

# Move to final location securely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Task evaluation exported successfully."
echo "=== Export complete ==="