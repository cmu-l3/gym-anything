#!/bin/bash
echo "=== Exporting agricultural_pathogen_classification results ==="

RESULTS_DIR="/home/ga/UGENE_Data/agriculture/results"
DISPLAY=:1 scrot /tmp/agricultural_pathogen_classification_end_screenshot.png 2>/dev/null || true

# --- Check PHYLIP alignment ---
PHY_EXISTS=false
PHY_VALID=false
PHY_SEQ_COUNT=0
if [ -f "${RESULTS_DIR}/pathogen_alignment.phy" ] && [ -s "${RESULTS_DIR}/pathogen_alignment.phy" ]; then
    PHY_EXISTS=true
    # PHYLIP format: first line has "N L" (num sequences, alignment length)
    FIRST_LINE=$(head -1 "${RESULTS_DIR}/pathogen_alignment.phy" | tr -s ' ')
    PHY_SEQ_COUNT=$(echo "$FIRST_LINE" | awk '{print $1}' 2>/dev/null || echo "0")
    if echo "$FIRST_LINE" | grep -qP '^\s*\d+\s+\d+'; then
        PHY_VALID=true
    fi
fi

# --- Check ClustalW alignment ---
ALN_EXISTS=false
ALN_VALID=false
ALN_SEQ_COUNT=0
if [ -f "${RESULTS_DIR}/pathogen_alignment.aln" ] && [ -s "${RESULTS_DIR}/pathogen_alignment.aln" ]; then
    ALN_EXISTS=true
    # ClustalW format starts with "CLUSTAL" or "MUSCLE" header
    if head -1 "${RESULTS_DIR}/pathogen_alignment.aln" | grep -qi "CLUSTAL\|MUSCLE\|UGENE"; then
        ALN_VALID=true
    fi
    ALN_SEQ_COUNT=$(grep -c "^[A-Za-z_]" "${RESULTS_DIR}/pathogen_alignment.aln" 2>/dev/null || echo "0")
    # Unique sequence names
    ALN_SEQ_COUNT=$(grep -oP '^[A-Za-z_][A-Za-z0-9_-]*' "${RESULTS_DIR}/pathogen_alignment.aln" 2>/dev/null | sort -u | wc -l)
fi

# --- Check Newick tree ---
NWK_EXISTS=false
NWK_VALID=false
NWK_LEAF_COUNT=0
NWK_HAS_UNKNOWN=false
NWK_HAS_FUSARIUM=false
if [ -f "${RESULTS_DIR}/pathogen_tree.nwk" ] && [ -s "${RESULTS_DIR}/pathogen_tree.nwk" ]; then
    NWK_EXISTS=true
    NWK_CONTENT=$(cat "${RESULTS_DIR}/pathogen_tree.nwk" 2>/dev/null)
    # Valid Newick: contains parentheses and ends with semicolon
    if echo "$NWK_CONTENT" | grep -qP '\(.*\).*;\s*$'; then
        NWK_VALID=true
    fi
    # Count leaf nodes (names before : or , or ))
    NWK_LEAF_COUNT=$(echo "$NWK_CONTENT" | grep -oP '[A-Za-z_][A-Za-z0-9_-]*(?=:|\)|,)' | sort -u | wc -l)
    echo "$NWK_CONTENT" | grep -qi "unknown\|Unknown" && NWK_HAS_UNKNOWN=true
    echo "$NWK_CONTENT" | grep -qi "fusarium\|Fusarium" && NWK_HAS_FUSARIUM=true
fi

# --- Check diagnostic report ---
REPORT_EXISTS=false
REPORT_HAS_FUSARIUM=false
REPORT_HAS_GRAMINEARUM=false
REPORT_HAS_MANAGEMENT=false
REPORT_HAS_UNKNOWN=false
REPORT_CONTENT=""
if [ -f "${RESULTS_DIR}/pathogen_diagnosis.txt" ] && [ -s "${RESULTS_DIR}/pathogen_diagnosis.txt" ]; then
    REPORT_EXISTS=true
    REPORT_CONTENT=$(cat "${RESULTS_DIR}/pathogen_diagnosis.txt" 2>/dev/null | head -80)
    echo "$REPORT_CONTENT" | grep -qi "fusarium\|Fusarium" && REPORT_HAS_FUSARIUM=true
    echo "$REPORT_CONTENT" | grep -qi "graminearum" && REPORT_HAS_GRAMINEARUM=true
    echo "$REPORT_CONTENT" | grep -qi "management\|treatment\|fungicide\|control\|recommend\|mitigation" && REPORT_HAS_MANAGEMENT=true
    echo "$REPORT_CONTENT" | grep -qi "unknown\|sample\|isolate\|patient\|farm" && REPORT_HAS_UNKNOWN=true
fi

# --- Build result JSON ---
python3 << PYEOF
import json
result = {
    "phy_exists": "${PHY_EXISTS}" == "true",
    "phy_valid": "${PHY_VALID}" == "true",
    "phy_seq_count": int("${PHY_SEQ_COUNT}" or "0"),
    "aln_exists": "${ALN_EXISTS}" == "true",
    "aln_valid": "${ALN_VALID}" == "true",
    "aln_seq_count": int("${ALN_SEQ_COUNT}" or "0"),
    "nwk_exists": "${NWK_EXISTS}" == "true",
    "nwk_valid": "${NWK_VALID}" == "true",
    "nwk_leaf_count": int("${NWK_LEAF_COUNT}" or "0"),
    "nwk_has_unknown": "${NWK_HAS_UNKNOWN}" == "true",
    "nwk_has_fusarium": "${NWK_HAS_FUSARIUM}" == "true",
    "report_exists": "${REPORT_EXISTS}" == "true",
    "report_has_fusarium": "${REPORT_HAS_FUSARIUM}" == "true",
    "report_has_graminearum": "${REPORT_HAS_GRAMINEARUM}" == "true",
    "report_has_management": "${REPORT_HAS_MANAGEMENT}" == "true",
    "report_has_unknown": "${REPORT_HAS_UNKNOWN}" == "true"
}
with open("/tmp/agricultural_pathogen_classification_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result JSON written")
PYEOF

echo "=== Export complete ==="
