#!/bin/bash
echo "=== Exporting environmental_metagenome_primer_design results ==="

RESULTS_DIR="/home/ga/UGENE_Data/environmental/results"
DISPLAY=:1 scrot /tmp/environmental_metagenome_primer_design_end_screenshot.png 2>/dev/null || true

# --- Check alignment FASTA ---
ALN_EXISTS=false
ALN_VALID=false
ALN_SEQ_COUNT=0
if [ -f "${RESULTS_DIR}/srb_alignment.fasta" ] && [ -s "${RESULTS_DIR}/srb_alignment.fasta" ]; then
    ALN_EXISTS=true
    if head -1 "${RESULTS_DIR}/srb_alignment.fasta" | grep -q "^>"; then
        ALN_VALID=true
    fi
    ALN_SEQ_COUNT=$(grep -c "^>" "${RESULTS_DIR}/srb_alignment.fasta" 2>/dev/null || echo "0")
fi

# --- Check primer design file ---
PRIMER_EXISTS=false
PRIMER_HAS_FORWARD=false
PRIMER_HAS_REVERSE=false
FORWARD_SEQ=""
REVERSE_SEQ=""
FORWARD_TM=""
REVERSE_TM=""
AMPLICON_SIZE=""
PRIMER_CONTENT=""

if [ -f "${RESULTS_DIR}/primer_design.txt" ] && [ -s "${RESULTS_DIR}/primer_design.txt" ]; then
    PRIMER_EXISTS=true
    PRIMER_CONTENT=$(cat "${RESULTS_DIR}/primer_design.txt" 2>/dev/null | head -50)

    # Extract forward primer sequence (look for DNA-like sequences near "forward")
    if echo "$PRIMER_CONTENT" | grep -qi "forward\|fwd\|left\|F:"; then
        PRIMER_HAS_FORWARD=true
        FORWARD_SEQ=$(echo "$PRIMER_CONTENT" | grep -iA1 "forward\|fwd\|left\|F:" | grep -oP '[ACGT]{18,30}' | head -1)
    fi
    # Try alternate: any line with 18-25 ACGT chars
    if [ -z "$FORWARD_SEQ" ]; then
        FORWARD_SEQ=$(echo "$PRIMER_CONTENT" | grep -oP '[ACGT]{18,30}' | head -1)
        [ -n "$FORWARD_SEQ" ] && PRIMER_HAS_FORWARD=true
    fi

    if echo "$PRIMER_CONTENT" | grep -qi "reverse\|rev\|right\|R:"; then
        PRIMER_HAS_REVERSE=true
        REVERSE_SEQ=$(echo "$PRIMER_CONTENT" | grep -iA1 "reverse\|rev\|right\|R:" | grep -oP '[ACGT]{18,30}' | head -1)
    fi
    if [ -z "$REVERSE_SEQ" ]; then
        REVERSE_SEQ=$(echo "$PRIMER_CONTENT" | grep -oP '[ACGT]{18,30}' | tail -1)
        [ -n "$REVERSE_SEQ" ] && [ "$REVERSE_SEQ" != "$FORWARD_SEQ" ] && PRIMER_HAS_REVERSE=true
    fi

    # Extract Tm values
    FORWARD_TM=$(echo "$PRIMER_CONTENT" | grep -iP 'forward.*tm|fwd.*tm|tm.*forward|F:.*\d+\.?\d*°?C' | grep -oP '\d+\.?\d*' | head -1)
    if [ -z "$FORWARD_TM" ]; then
        FORWARD_TM=$(echo "$PRIMER_CONTENT" | grep -oP 'Tm[:\s=]*\d+\.?\d*' | head -1 | grep -oP '\d+\.?\d*')
    fi
    REVERSE_TM=$(echo "$PRIMER_CONTENT" | grep -iP 'reverse.*tm|rev.*tm|tm.*reverse|R:.*\d+\.?\d*°?C' | grep -oP '\d+\.?\d*' | head -1)
    if [ -z "$REVERSE_TM" ]; then
        REVERSE_TM=$(echo "$PRIMER_CONTENT" | grep -oP 'Tm[:\s=]*\d+\.?\d*' | tail -1 | grep -oP '\d+\.?\d*')
    fi

    # Extract amplicon size
    AMPLICON_SIZE=$(echo "$PRIMER_CONTENT" | grep -iP 'amplicon|product|size|length' | grep -oP '\d{2,4}' | head -1)
    if [ -z "$AMPLICON_SIZE" ]; then
        AMPLICON_SIZE=$(echo "$PRIMER_CONTENT" | grep -oP '\d{3}\s*bp' | head -1 | grep -oP '\d+')
    fi
fi

# --- Check specificity report ---
REPORT_EXISTS=false
REPORT_HAS_VREGION=false
REPORT_HAS_SRB=false
REPORT_HAS_SPECIFICITY=false
REPORT_HAS_PCR_CONDITIONS=false
REPORT_HAS_ANNEALING_TEMP=false

if [ -f "${RESULTS_DIR}/primer_specificity_report.txt" ] && [ -s "${RESULTS_DIR}/primer_specificity_report.txt" ]; then
    REPORT_EXISTS=true
    REPORT_CONTENT=$(cat "${RESULTS_DIR}/primer_specificity_report.txt" 2>/dev/null | head -100)

    echo "$REPORT_CONTENT" | grep -qi "V3\|V4\|variable\|hypervariable\|region" && REPORT_HAS_VREGION=true
    echo "$REPORT_CONTENT" | grep -qi "sulfate.reducing\|SRB\|Desulfovibrio\|Desulfobulbus\|desulfo" && REPORT_HAS_SRB=true
    echo "$REPORT_CONTENT" | grep -qi "specific\|discriminat\|selective\|unique\|target" && REPORT_HAS_SPECIFICITY=true
    echo "$REPORT_CONTENT" | grep -qi "PCR\|anneal\|cycle\|denat\|extension\|condition" && REPORT_HAS_PCR_CONDITIONS=true
    echo "$REPORT_CONTENT" | grep -qP '\d{2}\s*°?C' && REPORT_HAS_ANNEALING_TEMP=true
fi

# --- Build result JSON ---
python3 << PYEOF
import json
result = {
    "aln_exists": "${ALN_EXISTS}" == "true",
    "aln_valid": "${ALN_VALID}" == "true",
    "aln_seq_count": int("${ALN_SEQ_COUNT}" or "0"),
    "primer_exists": "${PRIMER_EXISTS}" == "true",
    "primer_has_forward": "${PRIMER_HAS_FORWARD}" == "true",
    "primer_has_reverse": "${PRIMER_HAS_REVERSE}" == "true",
    "forward_seq": "${FORWARD_SEQ}",
    "reverse_seq": "${REVERSE_SEQ}",
    "forward_tm": "${FORWARD_TM}",
    "reverse_tm": "${REVERSE_TM}",
    "amplicon_size": "${AMPLICON_SIZE}",
    "report_exists": "${REPORT_EXISTS}" == "true",
    "report_has_vregion": "${REPORT_HAS_VREGION}" == "true",
    "report_has_srb": "${REPORT_HAS_SRB}" == "true",
    "report_has_specificity": "${REPORT_HAS_SPECIFICITY}" == "true",
    "report_has_pcr_conditions": "${REPORT_HAS_PCR_CONDITIONS}" == "true",
    "report_has_annealing_temp": "${REPORT_HAS_ANNEALING_TEMP}" == "true"
}
with open("/tmp/environmental_metagenome_primer_design_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result JSON written")
PYEOF

echo "=== Export complete ==="
