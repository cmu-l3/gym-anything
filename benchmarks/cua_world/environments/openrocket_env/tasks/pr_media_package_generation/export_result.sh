#!/bin/bash
# export_result.sh
echo "=== Exporting pr_media_package_generation result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

ORK_FILE="/home/ga/Documents/rockets/pr_rocket.ork"
PDF_FILE="/home/ga/Documents/exports/telemetry_plot.pdf"
PNG_FILE="/home/ga/Documents/exports/rocket_render.png"

ork_exists="false"
pdf_exists="false"
pdf_valid="false"
png_exists="false"

png_w=0
png_h=0

# Verify ORK existence
if [ -f "$ORK_FILE" ]; then
    ork_exists="true"
fi

# Verify PDF existence and magic bytes validity
if [ -f "$PDF_FILE" ]; then
    pdf_exists="true"
    if head -c 5 "$PDF_FILE" | grep -q "%PDF"; then
        pdf_valid="true"
    fi
fi

# Verify PNG existence and extract dimensions using identify
if [ -f "$PNG_FILE" ]; then
    png_exists="true"
    if command -v identify &> /dev/null; then
        DIM=$(identify -format "%w %h" "$PNG_FILE" 2>/dev/null || echo "0 0")
        png_w=$(echo "$DIM" | awk '{print $1}')
        png_h=$(echo "$DIM" | awk '{print $2}')
    fi
fi

# Construct result JSON securely using a temporary file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start": $TASK_START,
  "ork_exists": $ork_exists,
  "pdf_exists": $pdf_exists,
  "pdf_valid": $pdf_valid,
  "png_exists": $png_exists,
  "png_width": ${png_w:-0},
  "png_height": ${png_h:-0}
}
EOF

# Move temporary file securely to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON written:"
cat /tmp/task_result.json
echo "=== Export complete ==="