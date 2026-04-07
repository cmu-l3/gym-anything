#!/bin/bash

echo "=== Exporting perspective_painting_extraction result ==="

sleep 2

RESULT_EXISTS=false
RESULT_SIZE=0

if [ -f "/home/ga/Desktop/painting_corrected.png" ]; then
  RESULT_EXISTS=true
  RESULT_SIZE=$(stat -c%s /home/ga/Desktop/painting_corrected.png 2>/dev/null || echo 0)
  echo "Found painting_corrected.png (${RESULT_SIZE} bytes)"
  chown ga:ga /home/ga/Desktop/painting_corrected.png 2>/dev/null || true
else
  echo "painting_corrected.png not found on Desktop"
  echo "Available image files on Desktop:"
  find /home/ga/Desktop -maxdepth 1 \( -name "*.png" -o -name "*.jpg" \) -ls 2>/dev/null | head -10 || echo "  None found"
  echo "Checking Documents folder:"
  find /home/ga/Documents -maxdepth 1 \( -name "*.png" -o -name "*.jpg" \) -ls 2>/dev/null | head -5 || echo "  None found"
fi

# Collect file metadata into JSON
TASK_START=$(cat /tmp/perspective_painting_task_start 2>/dev/null || echo 0)
CURRENT_TIME=$(date +%s)

cat > /tmp/perspective_painting_result.json << JSONEOF
{
  "task_id": "perspective_painting_extraction",
  "result_exists": ${RESULT_EXISTS},
  "result_size_bytes": ${RESULT_SIZE},
  "task_start_timestamp": ${TASK_START},
  "export_timestamp": "${CURRENT_TIME}",
  "export_time_iso": "$(date -Iseconds)"
}
JSONEOF

echo "=== Export complete ==="
