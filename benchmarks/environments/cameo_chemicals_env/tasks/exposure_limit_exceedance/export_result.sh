#!/bin/bash
# export_result.sh - Post-task hook for exposure_limit_exceedance
# Exports agent's exceedance report for verification

echo "=== Exporting exposure_limit_exceedance result ==="

# Source shared utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true
echo "Final screenshot saved"

# Check output file
OUTPUT_FILE="/home/ga/Documents/exposure_exceedance_report.txt"
INITIAL_EXISTS=$(cat /tmp/initial_output_file_exists 2>/dev/null || echo "0")

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS=1
    FILE_SIZE=$(wc -c < "$OUTPUT_FILE")
    FILE_LINES=$(wc -l < "$OUTPUT_FILE")
    FILE_CONTENT=$(cat "$OUTPUT_FILE")
else
    FILE_EXISTS=0
    FILE_SIZE=0
    FILE_LINES=0
    FILE_CONTENT=""
fi

echo "Output file exists: $FILE_EXISTS"
echo "File size: $FILE_SIZE bytes"

# Check identification of exceedance zones
# Zone 2: Xylene exceeds PEL (115 vs 100 ppm)
IDENTIFIES_XYLENE_EXCEEDANCE=0
if echo "$FILE_CONTENT" | grep -qi "xylene\|zone 2\|zone2"; then
    IDENTIFIES_XYLENE_EXCEEDANCE=1
fi

# Zone 3: MEK exceeds PEL (255 vs 200 ppm)
IDENTIFIES_MEK_EXCEEDANCE=0
if echo "$FILE_CONTENT" | grep -qi "methyl ethyl ketone\|mek\|2-butanone\|zone 3\|zone3"; then
    IDENTIFIES_MEK_EXCEEDANCE=1
fi

# Zone 4: n-Hexane exceeds PEL (680 vs 500 ppm) — key zone (neuropathy)
IDENTIFIES_HEXANE_EXCEEDANCE=0
if echo "$FILE_CONTENT" | grep -qi "hexane\|n-hexane\|zone 4\|zone4"; then
    IDENTIFIES_HEXANE_EXCEEDANCE=1
fi

# Zone 5: Methanol exceeds PEL (400 vs 200 ppm)
IDENTIFIES_METHANOL_EXCEEDANCE=0
if echo "$FILE_CONTENT" | grep -qi "methanol\|methyl alcohol\|zone 5\|zone5"; then
    IDENTIFIES_METHANOL_EXCEEDANCE=1
fi

# Correctly identifies n-Hexane as cause of neuropathy
IDENTIFIES_HEXANE_NEUROPATHY=0
if echo "$FILE_CONTENT" | grep -qi "hexane" && echo "$FILE_CONTENT" | grep -qi "neuropath\|neurolog\|nervous system\|peripheral"; then
    IDENTIFIES_HEXANE_NEUROPATHY=1
fi

# Correctly identifies toluene and PERC as WITHIN limits (not flagged as exceedances)
# We check if the report is nuanced (doesn't just flag everything)
MENTIONS_TOLUENE=0
if echo "$FILE_CONTENT" | grep -qi "toluene"; then
    MENTIONS_TOLUENE=1
fi

# Mentions OSHA PEL, IDLH values
MENTIONS_PEL=0
if echo "$FILE_CONTENT" | grep -qi "pel\|permissible exposure\|osha"; then
    MENTIONS_PEL=1
fi

MENTIONS_IDLH=0
if echo "$FILE_CONTENT" | grep -qi "idlh\|immediately dangerous"; then
    MENTIONS_IDLH=1
fi

# Mentions corrective actions
MENTIONS_CORRECTIVE=0
if echo "$FILE_CONTENT" | grep -qi "corrective\|recommend\|ventilat\|control\|engineer\|ppe\|respirator\|administrative"; then
    MENTIONS_CORRECTIVE=1
fi

# Count exceedances correctly identified (out of 4: xylene, mek, hexane, methanol)
EXCEEDANCES_FOUND=0
for v in $IDENTIFIES_XYLENE_EXCEEDANCE $IDENTIFIES_MEK_EXCEEDANCE $IDENTIFIES_HEXANE_EXCEEDANCE $IDENTIFIES_METHANOL_EXCEEDANCE; do
    if [ "$v" -eq 1 ]; then
        EXCEEDANCES_FOUND=$((EXCEEDANCES_FOUND + 1))
    fi
done

echo "Xylene exceedance (Zone 2): $IDENTIFIES_XYLENE_EXCEEDANCE"
echo "MEK exceedance (Zone 3): $IDENTIFIES_MEK_EXCEEDANCE"
echo "n-Hexane exceedance (Zone 4): $IDENTIFIES_HEXANE_EXCEEDANCE"
echo "Methanol exceedance (Zone 5): $IDENTIFIES_METHANOL_EXCEEDANCE"
echo "Hexane/neuropathy connection: $IDENTIFIES_HEXANE_NEUROPATHY"
echo "Mentions PEL: $MENTIONS_PEL"
echo "Mentions IDLH: $MENTIONS_IDLH"
echo "Mentions corrective actions: $MENTIONS_CORRECTIVE"
echo "Total exceedances found: $EXCEEDANCES_FOUND / 4"

# Get task timing
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)
ELAPSED=$((TASK_END - TASK_START))

# Write result JSON
python3 - <<PYEOF
import json

result = {
    "task": "exposure_limit_exceedance",
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "file_lines": $FILE_LINES,
    "initial_file_existed": $INITIAL_EXISTS,
    "identifies_xylene_exceedance": $IDENTIFIES_XYLENE_EXCEEDANCE,
    "identifies_mek_exceedance": $IDENTIFIES_MEK_EXCEEDANCE,
    "identifies_hexane_exceedance": $IDENTIFIES_HEXANE_EXCEEDANCE,
    "identifies_methanol_exceedance": $IDENTIFIES_METHANOL_EXCEEDANCE,
    "identifies_hexane_neuropathy": $IDENTIFIES_HEXANE_NEUROPATHY,
    "exceedances_found": $EXCEEDANCES_FOUND,
    "mentions_pel": $MENTIONS_PEL,
    "mentions_idlh": $MENTIONS_IDLH,
    "mentions_corrective": $MENTIONS_CORRECTIVE,
    "mentions_toluene": $MENTIONS_TOLUENE,
    "elapsed_seconds": $ELAPSED,
}

with open("/tmp/exposure_limit_exceedance_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result JSON written to /tmp/exposure_limit_exceedance_result.json")
PYEOF

echo "=== Export complete ==="
