#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Compare Restoration Quality Result ==="

SNAPSHOT_DIR="/home/ga/Pictures/vlc"
SNAPSHOT_LOCATIONS=(
    "$SNAPSHOT_DIR"
    "/home/ga/Pictures"
    "/home/ga"
    "/home/ga/Downloads"
)

# Search for snapshots with identifying names
ORIGINAL_SNAPSHOT=""
RESTORED_SNAPSHOT=""

echo "Searching for snapshots..."

for location in "${SNAPSHOT_LOCATIONS[@]}"; do
    if [ ! -d "$location" ]; then
        continue
    fi
    
    # Look for PNG and JPG files modified in last 10 minutes
    for ext in png jpg jpeg PNG JPG JPEG; do
        for file in "$location"/*."$ext" 2>/dev/null; do
            if [ ! -f "$file" ]; then
                continue
            fi
            
            # Check if file was modified recently (within last 10 minutes)
            if [ $(find "$file" -mmin -10 2>/dev/null | wc -l) -eq 0 ]; then
                continue
            fi
            
            filename=$(basename "$file")
            filename_lower=$(echo "$filename" | tr '[:upper:]' '[:lower:]')
            
            # Check for original video snapshot
            if echo "$filename_lower" | grep -qE "(original|scan|unprocessed)"; then
                if [ -z "$ORIGINAL_SNAPSHOT" ]; then
                    ORIGINAL_SNAPSHOT="$file"
                    echo "Found original snapshot: $filename"
                fi
            fi
            
            # Check for restored video snapshot
            if echo "$filename_lower" | grep -qE "(restor|enhance|clean|service|fixed)"; then
                if [ -z "$RESTORED_SNAPSHOT" ]; then
                    RESTORED_SNAPSHOT="$file"
                    echo "Found restored snapshot: $filename"
                fi
            fi
        done
    done
done

# Copy snapshots if found
if [ -n "$ORIGINAL_SNAPSHOT" ] && [ -f "$ORIGINAL_SNAPSHOT" ]; then
    echo "✅ Copying original snapshot..."
    cp "$ORIGINAL_SNAPSHOT" /tmp/vlc_comparison_original.png
    ls -lh "$ORIGINAL_SNAPSHOT"
else
    echo "⚠️ Original snapshot not found"
fi

if [ -n "$RESTORED_SNAPSHOT" ] && [ -f "$RESTORED_SNAPSHOT" ]; then
    echo "✅ Copying restored snapshot..."
    cp "$RESTORED_SNAPSHOT" /tmp/vlc_comparison_restored.png
    ls -lh "$RESTORED_SNAPSHOT"
else
    echo "⚠️ Restored snapshot not found"
fi

# Count VLC processes (to check if multiple instances were used)
VLC_COUNT=0
if command -v pgrep &> /dev/null; then
    VLC_COUNT=$(pgrep -fc 'vlc' || echo "0")
    echo "VLC instances detected: $VLC_COUNT"
fi

# Create result JSON with metadata
cat > /tmp/vlc_comparison_result.json <<EOF
{
    "original_snapshot": "$([ -n "$ORIGINAL_SNAPSHOT" ] && echo "$ORIGINAL_SNAPSHOT" || echo "")",
    "restored_snapshot": "$([ -n "$RESTORED_SNAPSHOT" ] && echo "$RESTORED_SNAPSHOT" || echo "")",
    "vlc_instances": $VLC_COUNT,
    "both_found": $([ -n "$ORIGINAL_SNAPSHOT" ] && [ -n "$RESTORED_SNAPSHOT" ] && echo "true" || echo "false")
}
EOF

cat /tmp/vlc_comparison_result.json

# Close all VLC instances
if is_vlc_running; then
    echo "Closing VLC instances..."
    kill_vlc ga
    sleep 2
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_compare_completed.txt
echo "Comparison task completed" >> /tmp/vlc_compare_completed.txt

echo "=== Export Complete ==="