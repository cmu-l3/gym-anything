#!/bin/bash
# Export script for oncology_lesion_measurement task
echo "=== Exporting oncology_lesion_measurement result ==="

export DISPLAY=:1

TASK_START=$(cat /tmp/oncology_lesion_measurement_start_ts 2>/dev/null || echo "0")
EXPORTS_DIR="/home/ga/DICOM/exports"

# ------------------------------------------------------------------
# Take final screenshot
# ------------------------------------------------------------------
DISPLAY=:1 import -window root /tmp/oncology_lesion_measurement_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/oncology_lesion_measurement_end_screenshot.png 2>/dev/null || true

# ------------------------------------------------------------------
# Check lesion export images
# ------------------------------------------------------------------
check_file() {
    local FILE="$1"
    local EXISTS=false
    local IS_NEW=false
    local SIZE_KB=0

    if [ -f "$FILE" ]; then
        EXISTS=true
        MTIME=$(stat -c %Y "$FILE" 2>/dev/null || echo "0")
        if [ "$MTIME" -gt "$TASK_START" ]; then
            IS_NEW=true
        fi
        SIZE_BYTES=$(stat -c %s "$FILE" 2>/dev/null || echo "0")
        SIZE_KB=$((SIZE_BYTES / 1024))
    fi

    echo "$EXISTS $IS_NEW $SIZE_KB"
}

L1_INFO=$(check_file "$EXPORTS_DIR/recist_lesion1.png")
L2_INFO=$(check_file "$EXPORTS_DIR/recist_lesion2.png")
RPT_INFO=$(check_file "$EXPORTS_DIR/recist_report.txt")

L1_EXISTS=$(echo "$L1_INFO" | awk '{print $1}')
L1_NEW=$(echo "$L1_INFO" | awk '{print $2}')
L1_SIZE=$(echo "$L1_INFO" | awk '{print $3}')

L2_EXISTS=$(echo "$L2_INFO" | awk '{print $1}')
L2_NEW=$(echo "$L2_INFO" | awk '{print $2}')
L2_SIZE=$(echo "$L2_INFO" | awk '{print $3}')

RPT_EXISTS=$(echo "$RPT_INFO" | awk '{print $1}')
RPT_NEW=$(echo "$RPT_INFO" | awk '{print $2}')
RPT_SIZE_KB=$(echo "$RPT_INFO" | awk '{print $3}')

# Get actual byte size of report for content check
RPT_SIZE_BYTES=0
if [ -f "$EXPORTS_DIR/recist_report.txt" ]; then
    RPT_SIZE_BYTES=$(stat -c %s "$EXPORTS_DIR/recist_report.txt" 2>/dev/null || echo "0")
fi

# Count all new PNG files in exports directory (catches alternate naming)
NEW_PNG_COUNT=0
if [ -d "$EXPORTS_DIR" ]; then
    while IFS= read -r -d '' f; do
        FMTIME=$(stat -c %Y "$f" 2>/dev/null || echo "0")
        if [ "$FMTIME" -gt "$TASK_START" ]; then
            NEW_PNG_COUNT=$((NEW_PNG_COUNT + 1))
        fi
    done < <(find "$EXPORTS_DIR" -name "*.png" -print0 2>/dev/null)
fi

# ------------------------------------------------------------------
# Parse RECIST-specific content from report
# ------------------------------------------------------------------
SLD_VALUE=""
MEASUREMENT_COUNT=0
HAS_SLD=false
HAS_BASELINE_STATEMENT=false
HAS_TWO_LESIONS=false
WINDOW_MENTIONED=false

if [ "$RPT_EXISTS" = "true" ] && [ "$RPT_NEW" = "true" ]; then
    RPT_FILE="$EXPORTS_DIR/recist_report.txt"

    # Extract SLD value: look for "SLD: NNN" or "sum of longest diameters: NNN" or "total: NNN mm"
    SLD_VALUE=$(grep -oiE "(SLD|sum of longest|total)[^0-9]*([0-9]+(\.[0-9]+)?)" "$RPT_FILE" 2>/dev/null | \
        grep -oE "[0-9]+(\.[0-9]+)?" | head -1 || echo "")

    # Count distinct measurements: numbers followed by mm or just standalone measurements
    # Look for patterns like "XX mm", "XX.X mm", or decimal values in typical measurement range (5-300mm)
    MEASUREMENT_COUNT=$(grep -oE "\b([5-9][0-9]|[1-2][0-9]{2}|300)(\.[0-9]+)?\s*(mm)?" "$RPT_FILE" 2>/dev/null | wc -l || echo "0")

    # Check for SLD keyword
    if grep -qiE "(SLD|sum of longest|sum of diameters)" "$RPT_FILE" 2>/dev/null; then
        HAS_SLD=true
    fi

    # Check for baseline assessment statement
    if grep -qiE "(baseline|establishes|response monitoring|target lesion|RECIST)" "$RPT_FILE" 2>/dev/null; then
        HAS_BASELINE_STATEMENT=true
    fi

    # Check for two lesion mentions
    if grep -qiE "(lesion\s*[12]|target\s*[12]|measurement\s*[12])" "$RPT_FILE" 2>/dev/null; then
        HAS_TWO_LESIONS=true
    fi

    # Check for soft tissue window mention
    if grep -qiE "(soft tissue|window|W/L|WW|WL|400|50)" "$RPT_FILE" 2>/dev/null; then
        WINDOW_MENTIONED=true
    fi
fi

# ------------------------------------------------------------------
# Write result JSON
# ------------------------------------------------------------------
cat > /tmp/oncology_lesion_measurement_result.json << EOF
{
    "task_start": $TASK_START,
    "lesion1_image_exists": $L1_EXISTS,
    "lesion1_image_is_new": $L1_NEW,
    "lesion1_image_size_kb": $L1_SIZE,
    "lesion2_image_exists": $L2_EXISTS,
    "lesion2_image_is_new": $L2_NEW,
    "lesion2_image_size_kb": $L2_SIZE,
    "new_png_count": $NEW_PNG_COUNT,
    "report_exists": $RPT_EXISTS,
    "report_is_new": $RPT_NEW,
    "report_size_bytes": $RPT_SIZE_BYTES,
    "sld_value": "$SLD_VALUE",
    "measurement_count": $MEASUREMENT_COUNT,
    "has_sld_keyword": $HAS_SLD,
    "has_baseline_statement": $HAS_BASELINE_STATEMENT,
    "has_two_lesion_mentions": $HAS_TWO_LESIONS,
    "window_mentioned": $WINDOW_MENTIONED
}
EOF

echo "=== oncology_lesion_measurement export complete ==="
echo "Lesion1 image: exists=$L1_EXISTS new=$L1_NEW size=${L1_SIZE}KB"
echo "Lesion2 image: exists=$L2_EXISTS new=$L2_NEW size=${L2_SIZE}KB"
echo "New PNGs in exports: $NEW_PNG_COUNT"
echo "Report: exists=$RPT_EXISTS new=$RPT_NEW size=${RPT_SIZE_BYTES}B"
echo "SLD value found: '$SLD_VALUE'"
echo "Measurement count: $MEASUREMENT_COUNT"
echo "Has SLD keyword: $HAS_SLD"
cat /tmp/oncology_lesion_measurement_result.json
