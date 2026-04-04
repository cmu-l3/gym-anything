#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Batch Audio Balance Result ==="

RAW_DIR="/home/ga/Music/podcast_raw"
BALANCED_DIR="/home/ga/Music/podcast_balanced"
EXPORT_DIR="/tmp/vlc_audio_balance_export"

# Create export directory
mkdir -p "$EXPORT_DIR"

# Check for output files
if [ -d "$BALANCED_DIR" ] && [ "$(ls -A $BALANCED_DIR 2>/dev/null)" ]; then
    echo "✅ Balanced audio directory found with files:"
    ls -lh "$BALANCED_DIR"
    
    # Copy all output files to export directory
    cp "$BALANCED_DIR"/*.mp3 "$EXPORT_DIR/" 2>/dev/null || echo "No MP3 files found"
    
    # Count output files
    OUTPUT_COUNT=$(ls -1 "$BALANCED_DIR"/*.mp3 2>/dev/null | wc -l)
    echo "Output files: $OUTPUT_COUNT"
    echo "$OUTPUT_COUNT" > /tmp/vlc_audio_balance_output_count.txt
else
    echo "⚠️ Balanced audio directory not found or empty"
    echo "0" > /tmp/vlc_audio_balance_output_count.txt
fi

# Copy original files for verification
mkdir -p "$EXPORT_DIR/originals"
cp "$RAW_DIR"/*.mp3 "$EXPORT_DIR/originals/" 2>/dev/null || true

# Copy checksum and timestamp files
cp /tmp/vlc_audio_balance_originals.md5 "$EXPORT_DIR/" 2>/dev/null || true
cp /tmp/vlc_audio_balance_timestamps.txt "$EXPORT_DIR/" 2>/dev/null || true

# Create result metadata JSON
cat > /tmp/vlc_audio_balance_metadata.json <<EOF
{
    "raw_dir": "$RAW_DIR",
    "balanced_dir": "$BALANCED_DIR",
    "output_count": $(cat /tmp/vlc_audio_balance_output_count.txt),
    "export_dir": "$EXPORT_DIR",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "✅ Metadata saved"

# Close VLC
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_audio_balance_completed.txt
echo "Batch audio balance task completed" >> /tmp/vlc_audio_balance_completed.txt
echo "Output files: $(cat /tmp/vlc_audio_balance_output_count.txt)" >> /tmp/vlc_audio_balance_completed.txt

echo "=== Export Complete ==="