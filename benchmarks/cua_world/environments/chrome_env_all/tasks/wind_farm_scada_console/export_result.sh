#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Wind Farm SCADA Console Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if target PDF was downloaded
PDF_PATH="/home/ga/Documents/Field_Safety/LOTO_procedure_2026.pdf"
if [ -f "$PDF_PATH" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c %s "$PDF_PATH" 2>/dev/null || echo "0")
    PDF_MTIME=$(stat -c %Y "$PDF_PATH" 2>/dev/null || echo "0")
    
    if [ "$PDF_MTIME" -gt "$TASK_START" ]; then
        PDF_DOWNLOADED_DURING_TASK="true"
    else
        PDF_DOWNLOADED_DURING_TASK="false"
    fi
else
    PDF_EXISTS="false"
    PDF_SIZE="0"
    PDF_DOWNLOADED_DURING_TASK="false"
fi

# Create a temporary copy of the Web Data sqlite database before closing Chrome
# This helps prevent locking issues when analyzing custom search engines
mkdir -p /tmp/chrome_export
cp "/home/ga/.config/google-chrome/Default/Web Data" "/tmp/chrome_export/Web Data" 2>/dev/null || true

# Gracefully close Chrome to flush all JSON data (Bookmarks, Preferences, Local State)
echo "Closing Chrome to flush data to disk..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# Create JSON metadata export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "pdf_exists": $PDF_EXISTS,
    "pdf_downloaded_during_task": $PDF_DOWNLOADED_DURING_TASK,
    "pdf_size_bytes": $PDF_SIZE
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="