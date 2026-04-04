#!/bin/bash
echo "=== Exporting clinical_variant_annotation results ==="

TASK_START=$(cat /tmp/clinical_variant_annotation_start_ts 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/UGENE_Data/clinical/results"

DISPLAY=:1 scrot /tmp/clinical_variant_annotation_end_screenshot.png 2>/dev/null || true

# --- Check corrected GenBank file ---
CORRECTED_FILE="${RESULTS_DIR}/patient_BRCA1_corrected.gb"
FILE_EXISTS=false
VALID_GB=false
HAS_BRCA1_GENE=false
HAS_BRCA2_GENE=false
HAS_CDS=false
CDS_START=""
HAS_VARIATION=false
VARIATION_COUNT=0
VARIATION_POSITIONS=""
HAS_ORF_ANNOTATIONS=false
ORF_COUNT=0
FILE_CONTENT_SNIPPET=""

if [ -f "$CORRECTED_FILE" ] && [ -s "$CORRECTED_FILE" ]; then
    FILE_EXISTS=true
    CONTENT=$(cat "$CORRECTED_FILE" 2>/dev/null)
    FILE_CONTENT_SNIPPET=$(echo "$CONTENT" | head -60)

    # Valid GenBank?
    if echo "$CONTENT" | grep -q "^LOCUS" && echo "$CONTENT" | grep -q "^FEATURES"; then
        VALID_GB=true
    fi

    # Check gene name
    if echo "$CONTENT" | grep -qi '/gene="BRCA1"'; then
        HAS_BRCA1_GENE=true
    fi
    if echo "$CONTENT" | grep -qi '/gene="BRCA2"'; then
        HAS_BRCA2_GENE=true
    fi

    # Check CDS
    if echo "$CONTENT" | grep -q "CDS"; then
        HAS_CDS=true
        CDS_START=$(echo "$CONTENT" | grep -oP 'CDS\s+(\d+)' | head -1 | grep -oP '\d+')
    fi

    # Check variation annotations
    VARIATION_COUNT=$(echo "$CONTENT" | grep -ci "variation\|variant\|mutation\|SNP\|SNV\|deletion\|frameshift" || echo "0")
    if [ "$VARIATION_COUNT" -gt 0 ]; then
        HAS_VARIATION=true
    fi
    VARIATION_POSITIONS=$(echo "$CONTENT" | grep -B1 -i "variation\|variant\|mutation" | grep -oP '\d+\.\.\d+|\d+' | head -10 | tr '\n' ',')

    # Check ORF annotations
    ORF_COUNT=$(echo "$CONTENT" | grep -ci "ORF\|open_reading_frame\|misc_feature.*ORF" || echo "0")
    if [ "$ORF_COUNT" -gt 0 ]; then
        HAS_ORF_ANNOTATIONS=true
    fi
fi

# --- Check clinical report ---
REPORT_FILE="${RESULTS_DIR}/clinical_report.txt"
REPORT_EXISTS=false
REPORT_MENTIONS_BRCA1=false
REPORT_MENTIONS_CDS=false
REPORT_MENTIONS_VARIANT=false
REPORT_MENTIONS_DELETION=false
REPORT_MENTIONS_GENE_FIX=false
REPORT_CONTENT=""

if [ -f "$REPORT_FILE" ] && [ -s "$REPORT_FILE" ]; then
    REPORT_EXISTS=true
    REPORT_CONTENT=$(cat "$REPORT_FILE" 2>/dev/null | head -80)

    echo "$REPORT_CONTENT" | grep -qi "BRCA1" && REPORT_MENTIONS_BRCA1=true
    echo "$REPORT_CONTENT" | grep -qi "CDS\|coding\|exon\|boundary\|start" && REPORT_MENTIONS_CDS=true
    echo "$REPORT_CONTENT" | grep -qi "variant\|missense\|substitution\|C>T\|SNV\|SNP" && REPORT_MENTIONS_VARIANT=true
    echo "$REPORT_CONTENT" | grep -qi "deletion\|frameshift\|del\|indel" && REPORT_MENTIONS_DELETION=true
    echo "$REPORT_CONTENT" | grep -qi "BRCA2.*BRCA1\|gene.*correct\|gene.*fix\|renamed\|changed.*gene" && REPORT_MENTIONS_GENE_FIX=true
fi

# --- Build result JSON ---
python3 << PYEOF
import json

result = {
    "file_exists": "${FILE_EXISTS}" == "true",
    "valid_gb": "${VALID_GB}" == "true",
    "has_brca1_gene": "${HAS_BRCA1_GENE}" == "true",
    "has_brca2_gene": "${HAS_BRCA2_GENE}" == "true",
    "has_cds": "${HAS_CDS}" == "true",
    "cds_start": "${CDS_START}" if "${CDS_START}" else "",
    "has_variation": "${HAS_VARIATION}" == "true",
    "variation_count": int("${VARIATION_COUNT}" or "0"),
    "variation_positions": "${VARIATION_POSITIONS}",
    "has_orf_annotations": "${HAS_ORF_ANNOTATIONS}" == "true",
    "orf_count": int("${ORF_COUNT}" or "0"),
    "report_exists": "${REPORT_EXISTS}" == "true",
    "report_mentions_brca1": "${REPORT_MENTIONS_BRCA1}" == "true",
    "report_mentions_cds": "${REPORT_MENTIONS_CDS}" == "true",
    "report_mentions_variant": "${REPORT_MENTIONS_VARIANT}" == "true",
    "report_mentions_deletion": "${REPORT_MENTIONS_DELETION}" == "true",
    "report_mentions_gene_fix": "${REPORT_MENTIONS_GENE_FIX}" == "true"
}

with open("/tmp/clinical_variant_annotation_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result JSON written")
PYEOF

echo "=== Export complete ==="
