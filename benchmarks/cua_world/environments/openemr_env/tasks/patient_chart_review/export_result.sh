#!/bin/bash
# Export script for Patient Chart Review Task

echo "=== Exporting Patient Chart Review Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Target patient
PATIENT_PID=11
EXPECTED_FNAME="Mariana"
EXPECTED_LNAME="Hane"
EXPECTED_DOB="1978-06-24"
OUTPUT_FILE="/home/ga/Desktop/patient_summary.txt"

# Check if summary file exists
FILE_EXISTS="false"
FILE_LENGTH=0
FILE_CONTENT=""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_LENGTH=$(wc -c < "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_CONTENT=$(cat "$OUTPUT_FILE" 2>/dev/null || echo "")
    echo "Summary file found: $OUTPUT_FILE"
    echo "File length: $FILE_LENGTH characters"
else
    echo "Summary file NOT found at $OUTPUT_FILE"
    # Check alternative locations
    for ALT_PATH in "/home/ga/patient_summary.txt" "/tmp/patient_summary.txt" "/home/ga/Desktop/summary.txt"; do
        if [ -f "$ALT_PATH" ]; then
            echo "Found at alternative location: $ALT_PATH"
            FILE_EXISTS="true"
            FILE_LENGTH=$(wc -c < "$ALT_PATH" 2>/dev/null || echo "0")
            FILE_CONTENT=$(cat "$ALT_PATH" 2>/dev/null || echo "")
            break
        fi
    done
fi

# Check content for required elements
HAS_PATIENT_NAME="false"
HAS_DOB="false"
HAS_PROBLEMS="false"
HAS_MEDICATIONS="false"

if [ -n "$FILE_CONTENT" ]; then
    echo ""
    echo "=== Analyzing file content ==="

    # Check for patient name (case insensitive)
    if echo "$FILE_CONTENT" | grep -qi "Mariana.*Hane\|Hane.*Mariana"; then
        HAS_PATIENT_NAME="true"
        echo "Patient name found"
    else
        echo "Patient name NOT found"
    fi

    # Check for DOB (various formats)
    if echo "$FILE_CONTENT" | grep -qE "1978.06.24|1978-06-24|06/24/1978|June.*24.*1978|24.*June.*1978"; then
        HAS_DOB="true"
        echo "DOB found"
    else
        echo "DOB NOT found"
    fi

    # Check for medical problems section
    if echo "$FILE_CONTENT" | grep -qiE "problem|condition|diagnosis|medical|disease|disorder"; then
        HAS_PROBLEMS="true"
        echo "Medical problems section found"
    else
        echo "Medical problems section NOT found"
    fi

    # Check for medications section
    if echo "$FILE_CONTENT" | grep -qiE "medication|prescription|drug|medicine|rx"; then
        HAS_MEDICATIONS="true"
        echo "Medications section found"
    else
        echo "Medications section NOT found (may be ok if patient has none)"
    fi

    echo ""
    echo "=== File content preview (first 1000 chars) ==="
    echo "$FILE_CONTENT" | head -c 1000
    echo ""
fi

# Get ground truth from database for comparison
echo ""
echo "=== Ground truth from database ==="

PATIENT_DATA=$(openemr_query "SELECT fname, lname, DOB, sex, street, city, state FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
echo "Patient: $PATIENT_DATA"

PROBLEM_COUNT=$(cat /tmp/patient_problem_count 2>/dev/null || echo "0")
MED_COUNT=$(cat /tmp/patient_med_count 2>/dev/null || echo "0")
ENC_COUNT=$(cat /tmp/patient_enc_count 2>/dev/null || echo "0")

echo "Problems in DB: $PROBLEM_COUNT"
echo "Medications in DB: $MED_COUNT"
echo "Encounters in DB: $ENC_COUNT"

# Escape content for JSON (truncate to avoid huge JSON)
FILE_CONTENT_PREVIEW=$(echo "$FILE_CONTENT" | head -c 2000 | sed 's/"/\\"/g' | tr '\n' ' ' | tr '\r' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/chart_review_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "expected_name": "$EXPECTED_FNAME $EXPECTED_LNAME",
    "expected_dob": "$EXPECTED_DOB",
    "output_file": "$OUTPUT_FILE",
    "file_exists": $FILE_EXISTS,
    "file_length": $FILE_LENGTH,
    "content_checks": {
        "has_patient_name": $HAS_PATIENT_NAME,
        "has_dob": $HAS_DOB,
        "has_problems_section": $HAS_PROBLEMS,
        "has_medications_section": $HAS_MEDICATIONS
    },
    "ground_truth": {
        "problem_count": $PROBLEM_COUNT,
        "medication_count": $MED_COUNT,
        "encounter_count": $ENC_COUNT
    },
    "file_content_preview": "$FILE_CONTENT_PREVIEW",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/patient_chart_review_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/patient_chart_review_result.json
chmod 666 /tmp/patient_chart_review_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/patient_chart_review_result.json"
cat /tmp/patient_chart_review_result.json

echo ""
echo "=== Export Complete ==="
