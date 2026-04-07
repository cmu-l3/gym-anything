#!/bin/bash
set -euo pipefail

echo "=== Exporting Seed Bank Conservation Terminal Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_DIR="/home/ga/Documents/Field_Season_2026"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Safely close Chrome to flush SQLite and JSON DBs to disk
echo "Flushing Chrome data..."
pkill -f "chrome" || true
pkill -f "google-chrome" || true
sleep 3
pkill -9 -f "chrome" || true
sleep 1

# 3. Check for downloaded PDFs physically
PDFS_FOUND=0
for pdf in "USDA_PPQ_587.pdf" "CITES_Export_App.pdf" "Field_Collection_Manifest.pdf"; do
    if [ -f "$TARGET_DIR/$pdf" ]; then
        PDFS_FOUND=$((PDFS_FOUND + 1))
    fi
done

# 4. Package basic stats into task_result.json
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $(date +%s),
    "pdfs_found_on_disk": $PDFS_FOUND,
    "target_dir_exists": $([ -d "$TARGET_DIR" ] && echo "true" || echo "false")
}
EOF

rm -f /tmp/task_result.json
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="