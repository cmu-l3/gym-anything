#!/bin/bash
echo "=== Exporting forensic_str_profiling results ==="

TASK_START=$(cat /tmp/forensic_str_profiling_start_ts 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/UGENE_Data/forensic/results"

# Take end screenshot
DISPLAY=:1 scrot /tmp/forensic_str_profiling_end_screenshot.png 2>/dev/null || true

# --- Check annotated GenBank files ---
D13_EXISTS=false
D13_VALID_GB=false
D13_HAS_STR_ANNOTATION=false
D13_HAS_FORENSIC_GROUP=false
D13_ANNOTATION_COORDS=""
D13_CONTENT=""

VWA_EXISTS=false
VWA_VALID_GB=false
VWA_HAS_STR_ANNOTATION=false
VWA_HAS_FORENSIC_GROUP=false
VWA_ANNOTATION_COORDS=""
VWA_CONTENT=""

TH01_EXISTS=false
TH01_VALID_GB=false
TH01_HAS_STR_ANNOTATION=false
TH01_HAS_FORENSIC_GROUP=false
TH01_ANNOTATION_COORDS=""
TH01_CONTENT=""

for LOCUS in D13S317 vWA TH01; do
    FILE="${RESULTS_DIR}/${LOCUS}_annotated.gb"
    if [ -f "$FILE" ] && [ -s "$FILE" ]; then
        CONTENT=$(cat "$FILE" 2>/dev/null)

        FILE_EXISTS=true

        # Check valid GenBank format
        VALID_GB=false
        if echo "$CONTENT" | grep -q "^LOCUS" && echo "$CONTENT" | grep -q "^FEATURES" && echo "$CONTENT" | grep -q "^ORIGIN"; then
            VALID_GB=true
        fi

        # Check for STR_core_repeat annotation
        HAS_STR=false
        if echo "$CONTENT" | grep -qi "STR_core_repeat\|str_core_repeat"; then
            HAS_STR=true
        fi

        # Check for forensic_markers group
        HAS_GROUP=false
        if echo "$CONTENT" | grep -qi "forensic_markers\|forensic"; then
            HAS_GROUP=true
        fi

        # Extract annotation coordinates (look for lines with number..number pattern near STR annotation)
        COORDS=$(echo "$CONTENT" | grep -oP '\d+\.\.\d+' | head -5)

        case "$LOCUS" in
            D13S317)
                D13_EXISTS=$FILE_EXISTS
                D13_VALID_GB=$VALID_GB
                D13_HAS_STR_ANNOTATION=$HAS_STR
                D13_HAS_FORENSIC_GROUP=$HAS_GROUP
                D13_ANNOTATION_COORDS="$COORDS"
                D13_CONTENT=$(echo "$CONTENT" | head -80)
                ;;
            vWA)
                VWA_EXISTS=$FILE_EXISTS
                VWA_VALID_GB=$VALID_GB
                VWA_HAS_STR_ANNOTATION=$HAS_STR
                VWA_HAS_FORENSIC_GROUP=$HAS_GROUP
                VWA_ANNOTATION_COORDS="$COORDS"
                VWA_CONTENT=$(echo "$CONTENT" | head -80)
                ;;
            TH01)
                TH01_EXISTS=$FILE_EXISTS
                TH01_VALID_GB=$VALID_GB
                TH01_HAS_STR_ANNOTATION=$HAS_STR
                TH01_HAS_FORENSIC_GROUP=$HAS_GROUP
                TH01_ANNOTATION_COORDS="$COORDS"
                TH01_CONTENT=$(echo "$CONTENT" | head -80)
                ;;
        esac
    fi
done

# --- Check report file ---
REPORT_EXISTS=false
REPORT_CONTENT=""
REPORT_HAS_D13=false
REPORT_HAS_VWA=false
REPORT_HAS_TH01=false
REPORT_HAS_TATC=false
REPORT_HAS_AGAT=false
REPORT_HAS_TCTA=false
REPORT_HAS_AATG=false
REPORT_HAS_TCAT=false

REPORT_FILE="${RESULTS_DIR}/str_profile_report.txt"
if [ -f "$REPORT_FILE" ] && [ -s "$REPORT_FILE" ]; then
    REPORT_EXISTS=true
    REPORT_CONTENT=$(cat "$REPORT_FILE" 2>/dev/null | head -100)

    echo "$REPORT_CONTENT" | grep -qi "D13S317" && REPORT_HAS_D13=true
    echo "$REPORT_CONTENT" | grep -qi "vWA\|vwa\|VWA" && REPORT_HAS_VWA=true
    echo "$REPORT_CONTENT" | grep -qi "TH01\|th01" && REPORT_HAS_TH01=true
    echo "$REPORT_CONTENT" | grep -qi "TATC\|tatc" && REPORT_HAS_TATC=true
    echo "$REPORT_CONTENT" | grep -qi "AGAT\|agat" && REPORT_HAS_AGAT=true
    echo "$REPORT_CONTENT" | grep -qi "TCTA\|tcta" && REPORT_HAS_TCTA=true
    echo "$REPORT_CONTENT" | grep -qi "AATG\|aatg" && REPORT_HAS_AATG=true
    echo "$REPORT_CONTENT" | grep -qi "TCAT\|tcat" && REPORT_HAS_TCAT=true
fi

# --- Count total output files ---
RESULT_FILE_COUNT=$(ls "${RESULTS_DIR}"/*.gb 2>/dev/null | wc -l)

# --- Build result JSON ---
python3 << PYEOF
import json

result = {
    "task_start_ts": int("${TASK_START}" or "0"),
    "d13_exists": "${D13_EXISTS}" == "true",
    "d13_valid_gb": "${D13_VALID_GB}" == "true",
    "d13_has_str_annotation": "${D13_HAS_STR_ANNOTATION}" == "true",
    "d13_has_forensic_group": "${D13_HAS_FORENSIC_GROUP}" == "true",
    "d13_annotation_coords": """${D13_ANNOTATION_COORDS}""".strip(),
    "vwa_exists": "${VWA_EXISTS}" == "true",
    "vwa_valid_gb": "${VWA_VALID_GB}" == "true",
    "vwa_has_str_annotation": "${VWA_HAS_STR_ANNOTATION}" == "true",
    "vwa_has_forensic_group": "${VWA_HAS_FORENSIC_GROUP}" == "true",
    "vwa_annotation_coords": """${VWA_ANNOTATION_COORDS}""".strip(),
    "th01_exists": "${TH01_EXISTS}" == "true",
    "th01_valid_gb": "${TH01_VALID_GB}" == "true",
    "th01_has_str_annotation": "${TH01_HAS_STR_ANNOTATION}" == "true",
    "th01_has_forensic_group": "${TH01_HAS_FORENSIC_GROUP}" == "true",
    "th01_annotation_coords": """${TH01_ANNOTATION_COORDS}""".strip(),
    "report_exists": "${REPORT_EXISTS}" == "true",
    "report_has_d13": "${REPORT_HAS_D13}" == "true",
    "report_has_vwa": "${REPORT_HAS_VWA}" == "true",
    "report_has_th01": "${REPORT_HAS_TH01}" == "true",
    "report_has_tatc_or_agat": "${REPORT_HAS_TATC}" == "true" or "${REPORT_HAS_AGAT}" == "true",
    "report_has_tcta": "${REPORT_HAS_TCTA}" == "true",
    "report_has_aatg": "${REPORT_HAS_AATG}" == "true",
    "report_has_tcat": "${REPORT_HAS_TCAT}" == "true",
    "result_file_count": int("${RESULT_FILE_COUNT}" or "0"),
    "report_content_snippet": """${REPORT_CONTENT}"""[:500] if """${REPORT_CONTENT}""" else ""
}

with open("/tmp/forensic_str_profiling_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result JSON written")
PYEOF

echo "=== Export complete ==="
