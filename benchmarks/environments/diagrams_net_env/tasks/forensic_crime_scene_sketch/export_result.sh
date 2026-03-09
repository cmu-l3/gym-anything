#!/bin/bash
echo "=== Exporting Task Results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Existence and Timestamps
DRAWIO_FILE="/home/ga/Diagrams/case_402_sketch.drawio"
PDF_FILE="/home/ga/Diagrams/case_402_exhibit.pdf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

check_file() {
    local f="$1"
    if [ -f "$f" ]; then
        local mtime=$(stat -c %Y "$f")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true"
        else
            echo "false"
        fi
    else
        echo "false"
    fi
}

DRAWIO_EXISTS=$( [ -f "$DRAWIO_FILE" ] && echo "true" || echo "false" )
DRAWIO_MODIFIED=$(check_file "$DRAWIO_FILE")
PDF_EXISTS=$( [ -f "$PDF_FILE" ] && echo "true" || echo "false" )
PDF_MODIFIED=$(check_file "$PDF_FILE")

# 3. Create JSON Result
# We do NOT parse the XML here in bash. We export the file status.
# The verifier.py will copy the .drawio file out and parse it using Python.

cat > /tmp/task_result.json << EOF
{
    "drawio_exists": $DRAWIO_EXISTS,
    "drawio_modified": $DRAWIO_MODIFIED,
    "pdf_exists": $PDF_EXISTS,
    "pdf_modified": $PDF_MODIFIED,
    "drawio_path": "$DRAWIO_FILE",
    "pdf_path": "$PDF_FILE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Results exported to /tmp/task_result.json"