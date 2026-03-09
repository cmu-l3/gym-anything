#!/bin/bash

echo "=== Exporting photo_retouch result ==="

sleep 2

RESULT_EXISTS=false

if [ -f "/home/ga/Desktop/retouched_portrait.png" ]; then
  RESULT_EXISTS=true
  SIZE=$(stat -c%s /home/ga/Desktop/retouched_portrait.png 2>/dev/null || echo 0)
  echo "Found retouched_portrait.png (${SIZE} bytes)"
  chown ga:ga /home/ga/Desktop/retouched_portrait.png 2>/dev/null || true
else
  echo "retouched_portrait.png not found on Desktop"
  echo "Available image files on Desktop:"
  find /home/ga/Desktop -name "*.png" -o -name "*.jpg" 2>/dev/null | head -5 || echo "None"
fi

cat > /tmp/photo_retouch_result.json << JSONEOF
{
  "result_exists": ${RESULT_EXISTS},
  "export_timestamp": "$(date -Iseconds)"
}
JSONEOF

echo "=== Export complete ==="
