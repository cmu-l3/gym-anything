#!/bin/bash
echo "=== Exporting vaccine_epitope_conservation results ==="

RESULTS_DIR="/home/ga/UGENE_Data/vaccine/results"
DISPLAY=:1 scrot /tmp/vaccine_epitope_conservation_end_screenshot.png 2>/dev/null || true

# --- Check consensus FASTA ---
CONSENSUS_EXISTS=false
CONSENSUS_VALID=false
CONSENSUS_LENGTH=0
if [ -f "${RESULTS_DIR}/HA_consensus.fasta" ] && [ -s "${RESULTS_DIR}/HA_consensus.fasta" ]; then
    CONSENSUS_EXISTS=true
    if head -1 "${RESULTS_DIR}/HA_consensus.fasta" | grep -q "^>"; then
        CONSENSUS_VALID=true
    fi
    CONSENSUS_LENGTH=$(grep -v "^>" "${RESULTS_DIR}/HA_consensus.fasta" 2>/dev/null | tr -d '\n' | wc -c)
fi

# --- Check annotated alignment ---
ALN_EXISTS=false
ALN_VALID=false
ALN_HAS_EPITOPE_ANNOTATION=false
ALN_HAS_VACCINE_GROUP=false
ALN_SEQ_COUNT=0
ALN_CONTENT=""
if [ -f "${RESULTS_DIR}/HA_alignment_annotated.aln" ] && [ -s "${RESULTS_DIR}/HA_alignment_annotated.aln" ]; then
    ALN_EXISTS=true
    ALN_CONTENT=$(cat "${RESULTS_DIR}/HA_alignment_annotated.aln" 2>/dev/null)
    if echo "$ALN_CONTENT" | head -1 | grep -qi "CLUSTAL\|MUSCLE\|UGENE\|MAFFT"; then
        ALN_VALID=true
    fi
    ALN_SEQ_COUNT=$(echo "$ALN_CONTENT" | grep -oP '^[A-Za-z_][A-Za-z0-9_/.-]*' | sort -u | wc -l)
fi

# Check if annotations exist in a separate UGENE annotation file or within the alignment
# UGENE may save annotations alongside the .aln file
EPITOPE_ANNOTATION_COUNT=0
for ANNOT_FILE in "${RESULTS_DIR}"/*.aln "${RESULTS_DIR}"/*.gb "${RESULTS_DIR}"/*annotation* "${RESULTS_DIR}"/*.ugene*; do
    if [ -f "$ANNOT_FILE" ]; then
        COUNT=$(grep -ci "conserved_epitope\|conserved.epitope" "$ANNOT_FILE" 2>/dev/null || echo "0")
        EPITOPE_ANNOTATION_COUNT=$((EPITOPE_ANNOTATION_COUNT + COUNT))
        grep -qi "conserved_epitope" "$ANNOT_FILE" 2>/dev/null && ALN_HAS_EPITOPE_ANNOTATION=true
        grep -qi "vaccine_targets\|vaccine.targets" "$ANNOT_FILE" 2>/dev/null && ALN_HAS_VACCINE_GROUP=true
    fi
done

# Also check any .csv or annotation export files
for F in "${RESULTS_DIR}"/*.csv "${RESULTS_DIR}"/*.tsv "${RESULTS_DIR}"/*.txt; do
    if [ -f "$F" ] && [ "$F" != "${RESULTS_DIR}/epitope_report.txt" ]; then
        grep -qi "conserved_epitope" "$F" 2>/dev/null && ALN_HAS_EPITOPE_ANNOTATION=true
    fi
done

# --- Check annotation coordinates (from any file containing them) ---
EPITOPE_COORDS=""
for F in "${RESULTS_DIR}"/*; do
    if [ -f "$F" ]; then
        COORDS=$(grep -i "conserved_epitope" "$F" 2>/dev/null | grep -oP '\d+\.\.\d+|\d+\s*-\s*\d+' | head -10)
        if [ -n "$COORDS" ]; then
            EPITOPE_COORDS="$COORDS"
            break
        fi
    fi
done

# Check coordinate spans (epitopes should be >= 9 residues)
VALID_EPITOPE_COUNT=0
if [ -n "$EPITOPE_COORDS" ]; then
    while IFS= read -r coord; do
        START=$(echo "$coord" | grep -oP '^\d+')
        END=$(echo "$coord" | grep -oP '\d+$')
        if [ -n "$START" ] && [ -n "$END" ]; then
            SPAN=$((END - START + 1))
            if [ "$SPAN" -ge 9 ]; then
                VALID_EPITOPE_COUNT=$((VALID_EPITOPE_COUNT + 1))
            fi
        fi
    done <<< "$EPITOPE_COORDS"
fi

# --- Check Stockholm format ---
STO_EXISTS=false
STO_VALID=false
if [ -f "${RESULTS_DIR}/HA_alignment.sto" ] && [ -s "${RESULTS_DIR}/HA_alignment.sto" ]; then
    STO_EXISTS=true
    if head -1 "${RESULTS_DIR}/HA_alignment.sto" | grep -q "STOCKHOLM"; then
        STO_VALID=true
    fi
fi

# --- Check epitope report ---
REPORT_EXISTS=false
REPORT_HAS_POSITIONS=false
REPORT_HAS_CONSERVATION_PCT=false
REPORT_HAS_RANKING=false
REPORT_HAS_COUNT=false
if [ -f "${RESULTS_DIR}/epitope_report.txt" ] && [ -s "${RESULTS_DIR}/epitope_report.txt" ]; then
    REPORT_EXISTS=true
    REPORT_CONTENT=$(cat "${RESULTS_DIR}/epitope_report.txt" 2>/dev/null | head -100)
    echo "$REPORT_CONTENT" | grep -qP '\d+\s*[-–.]\s*\d+' && REPORT_HAS_POSITIONS=true
    echo "$REPORT_CONTENT" | grep -qP '\d+\.?\d*\s*%' && REPORT_HAS_CONSERVATION_PCT=true
    echo "$REPORT_CONTENT" | grep -qi "rank\|top\|#1\|#2\|#3\|first\|second\|third\|best\|candidate" && REPORT_HAS_RANKING=true
    echo "$REPORT_CONTENT" | grep -qP 'total|count|found|identified.*\d+|\d+.*epitope' && REPORT_HAS_COUNT=true
fi

# --- Build result JSON ---
python3 << PYEOF
import json
result = {
    "consensus_exists": "${CONSENSUS_EXISTS}" == "true",
    "consensus_valid": "${CONSENSUS_VALID}" == "true",
    "consensus_length": int("${CONSENSUS_LENGTH}" or "0"),
    "aln_exists": "${ALN_EXISTS}" == "true",
    "aln_valid": "${ALN_VALID}" == "true",
    "aln_seq_count": int("${ALN_SEQ_COUNT}" or "0"),
    "aln_has_epitope_annotation": "${ALN_HAS_EPITOPE_ANNOTATION}" == "true",
    "aln_has_vaccine_group": "${ALN_HAS_VACCINE_GROUP}" == "true",
    "epitope_annotation_count": int("${EPITOPE_ANNOTATION_COUNT}" or "0"),
    "valid_epitope_count": int("${VALID_EPITOPE_COUNT}" or "0"),
    "sto_exists": "${STO_EXISTS}" == "true",
    "sto_valid": "${STO_VALID}" == "true",
    "report_exists": "${REPORT_EXISTS}" == "true",
    "report_has_positions": "${REPORT_HAS_POSITIONS}" == "true",
    "report_has_conservation_pct": "${REPORT_HAS_CONSERVATION_PCT}" == "true",
    "report_has_ranking": "${REPORT_HAS_RANKING}" == "true",
    "report_has_count": "${REPORT_HAS_COUNT}" == "true"
}
with open("/tmp/vaccine_epitope_conservation_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result JSON written")
PYEOF

echo "=== Export complete ==="
