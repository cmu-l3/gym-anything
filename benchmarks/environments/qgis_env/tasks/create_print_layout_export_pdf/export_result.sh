#!/bin/bash
echo "=== Exporting create_print_layout_export_pdf result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi
if ! type is_qgis_running &>/dev/null; then
    is_qgis_running() { pgrep -f "qgis" > /dev/null; }
fi

take_screenshot /tmp/task_end.png

EXPORT_DIR="/home/ga/GIS_Data/exports"
EXPECTED_FILE="$EXPORT_DIR/sample_map.pdf"

INITIAL_COUNT=$(cat /tmp/initial_pdf_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(ls -1 "$EXPORT_DIR"/*.pdf 2>/dev/null | wc -l || echo "0")

# Analyze PDF output
PDF_EXISTS="false"
PDF_SIZE=0
PDF_VALID="false"
PDF_HAS_CONTENT="false"
PDF_PAGE_COUNT=0

if [ -f "$EXPECTED_FILE" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c%s "$EXPECTED_FILE" 2>/dev/null || echo "0")

    # Check if it's a valid PDF
    if head -c 5 "$EXPECTED_FILE" 2>/dev/null | grep -q '%PDF'; then
        PDF_VALID="true"
    fi

    # Check for substantial content (not just a blank page)
    if [ "$PDF_SIZE" -gt 50000 ]; then
        PDF_HAS_CONTENT="true"
    fi

    # Try to get page count using pdfinfo or python
    PDF_PAGE_COUNT=$(python3 -c "
try:
    with open('$EXPECTED_FILE', 'rb') as f:
        content = f.read()
    # Count page markers in PDF
    import re
    pages = len(re.findall(b'/Type\s*/Page[^s]', content))
    print(max(pages, 1) if b'%PDF' in content[:10] else 0)
except:
    print(0)
" 2>/dev/null || echo "0")

else
    # Check for alternative PDF
    ALT=$(find "$EXPORT_DIR" -name "*.pdf" -mmin -10 2>/dev/null | head -1)
    if [ -n "$ALT" ]; then
        PDF_EXISTS="true"
        PDF_SIZE=$(stat -c%s "$ALT" 2>/dev/null || echo "0")
        EXPECTED_FILE="$ALT"
        if head -c 5 "$ALT" 2>/dev/null | grep -q '%PDF'; then
            PDF_VALID="true"
        fi
        if [ "$PDF_SIZE" -gt 50000 ]; then
            PDF_HAS_CONTENT="true"
        fi
    fi
fi

# Close QGIS
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

cat > /tmp/task_result.json << EOF
{
    "initial_pdf_count": $INITIAL_COUNT,
    "current_pdf_count": $CURRENT_COUNT,
    "pdf_exists": $PDF_EXISTS,
    "pdf_path": "$EXPECTED_FILE",
    "pdf_size_bytes": $PDF_SIZE,
    "pdf_valid": $PDF_VALID,
    "pdf_has_content": $PDF_HAS_CONTENT,
    "pdf_page_count": $PDF_PAGE_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="
