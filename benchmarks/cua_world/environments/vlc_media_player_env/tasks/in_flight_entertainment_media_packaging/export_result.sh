#!/bin/bash
echo "=== Exporting IFE Media Packaging task ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create a safe export directory for output files
mkdir -p /tmp/ife_outputs

JSON_FILE="/tmp/ife_export.json"
cat > "$JSON_FILE" << EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "files_mtime": {
EOF

FIRST=true

# Copy all generated .ts files and record their modification timestamps
for f in /home/ga/Videos/IFE_Ready/*.ts; do
  if [ -f "$f" ]; then
    fname=$(basename "$f")
    mtime=$(stat -c %Y "$f" 2>/dev/null || echo "0")
    
    # Copy to tmp so verifier can easily fetch them
    cp -f "$f" "/tmp/ife_outputs/$fname" 2>/dev/null || true
    
    if [ "$FIRST" = true ]; then
      FIRST=false
    else
      echo "," >> "$JSON_FILE"
    fi
    echo "    \"$fname\": $mtime" >> "$JSON_FILE"
  fi
done

cat >> "$JSON_FILE" << EOF
  }
}
EOF

# Copy the manifest if the agent created it
cp -f /home/ga/Documents/ife_manifest.json /tmp/ife_manifest.json 2>/dev/null || true

# Take final screenshot for trajectory checking
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

echo "Export complete. Results packaged in /tmp/ife_outputs/ and /tmp/ife_export.json"