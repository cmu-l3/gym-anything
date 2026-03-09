#!/usr/bin/env bash
# set -euo pipefail

echo "=== OSWorld Chrome Task Export: e1e75309-3ddb-4d09-92ec-de869c928143 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Take a final screenshot
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

START_TS=$(cat /tmp/task_start_ts 2>/dev/null || echo 0)
LATEST_PDF=$(find /home/ga/Desktop -maxdepth 1 -type f -name '*.pdf' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
PDF_EXISTS=false
PDF_CREATED_DURING_TASK=false
PDF_SIZE_BYTES=0

if [ -n "$LATEST_PDF" ] && [ -f "$LATEST_PDF" ]; then
    PDF_EXISTS=true
    MODIFIED_TS=$(stat -c %Y "$LATEST_PDF" 2>/dev/null || echo 0)
    PDF_SIZE_BYTES=$(stat -c %s "$LATEST_PDF" 2>/dev/null || echo 0)
    if [ "$MODIFIED_TS" -ge "$START_TS" ]; then
        PDF_CREATED_DURING_TASK=true
    fi
    cp "$LATEST_PDF" /tmp/generated_output.pdf 2>/dev/null || true
fi

cat > /tmp/pdf_export_result.json <<EOF
{
  "pdf_exists": $PDF_EXISTS,
  "pdf_created_during_task": $PDF_CREATED_DURING_TASK,
  "pdf_path": "${LATEST_PDF:-}",
  "pdf_size_bytes": $PDF_SIZE_BYTES
}
EOF

echo "✅ Export complete"
