#!/bin/bash
set -e
echo "=== Exporting results for import_contacts_csv ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_abook_mtime.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_contact_count.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Package Thunderbird address book files for the verifier
EXPORT_DIR="/tmp/thunderbird_export"
mkdir -p "$EXPORT_DIR"

PROFILE_DIR="/home/ga/.thunderbird/default-release"
ABOOK="${PROFILE_DIR}/abook.sqlite"

FINAL_MTIME="0"
if [ -f "$ABOOK" ]; then
    # Force Thunderbird to flush writes by copying
    cp "$ABOOK" "${EXPORT_DIR}/abook.sqlite"
    FINAL_MTIME=$(stat -c %Y "$ABOOK" 2>/dev/null || echo "0")
    echo "Exported abook.sqlite"
else
    echo "WARNING: abook.sqlite not found"
fi

# Grab any auxiliary address books just in case Thunderbird created a new one
for f in "${PROFILE_DIR}"/abook-*.sqlite; do
    if [ -f "$f" ]; then
        cp "$f" "${EXPORT_DIR}/$(basename "$f")"
        echo "Exported $(basename "$f")"
    fi
done

# Check if Thunderbird is still running
APP_RUNNING=$(pgrep -f "thunderbird" > /dev/null && echo "true" || echo "false")

# Create JSON metadata for the verifier
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_abook_mtime": $INITIAL_MTIME,
    "final_abook_mtime": $FINAL_MTIME,
    "initial_contact_count": $INITIAL_COUNT,
    "app_was_running": $APP_RUNNING
}
EOF

# Move JSON to final location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Archive the export directory so it can be copied easily
cd /tmp
tar -czf thunderbird_export.tar.gz -C thunderbird_export .
chmod 666 /tmp/thunderbird_export.tar.gz

echo "Export packaged at /tmp/thunderbird_export.tar.gz"
echo "Result metadata saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="