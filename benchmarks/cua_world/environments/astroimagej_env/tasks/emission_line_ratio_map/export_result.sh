#!/bin/bash
echo "=== Exporting Emission Line Ratio Map result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot as evidence
take_screenshot /tmp/task_final.png

# Check for expected output files
FITS_PATH="/home/ga/AstroImages/processed/sii_halpha_ratio.fits"
PNG_PATH="/home/ga/AstroImages/processed/sii_halpha_ratio.png"

FITS_EXISTS="false"
PNG_EXISTS="false"
FITS_CREATED="false"
PNG_CREATED="false"

# Check FITS
if [ -f "$FITS_PATH" ]; then
    FITS_EXISTS="true"
    MTIME=$(stat -c %Y "$FITS_PATH")
    if [ "$MTIME" -ge "$TASK_START" ]; then
        FITS_CREATED="true"
    fi
fi

# Check PNG
if [ -f "$PNG_PATH" ]; then
    PNG_EXISTS="true"
    MTIME=$(stat -c %Y "$PNG_PATH")
    if [ "$MTIME" -ge "$TASK_START" ]; then
        PNG_CREATED="true"
    fi
fi

# Export properties to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "fits_exists": $FITS_EXISTS,
    "png_exists": $PNG_EXISTS,
    "fits_created_during_task": $FITS_CREATED,
    "png_created_during_task": $PNG_CREATED,
    "task_start_time": $TASK_START
}
EOF

# Move to final accessible location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="