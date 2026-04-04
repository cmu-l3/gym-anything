#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Fix Subtitle Encoding Result ==="

# Initialize result variables
VLCRC_ENCODING=""
CONVERTED_FILE_FOUND="false"
CONVERTED_FILE_PATH=""

# Check VLC configuration for encoding setting
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    echo "Checking VLC configuration..."
    
    # Look for subtitle encoding setting
    if grep -q "subsdec-encoding=" "$VLC_RC"; then
        VLCRC_ENCODING=$(grep "^subsdec-encoding=" "$VLC_RC" | cut -d= -f2 | head -1)
        echo "Found subtitle encoding in vlcrc: $VLCRC_ENCODING"
    fi
    
    # Copy VLC config for verification
    cp "$VLC_RC" /tmp/vlc_subtitle_encoding_vlcrc.txt
else
    echo "⚠️ VLC config not found"
fi

# Check for converted subtitle files
SUBTITLE_DIR="/home/ga/Videos/subtitles"
echo "Checking for converted subtitle files..."

# Look for any UTF-8 encoded .srt files (excluding the broken one)
for srt_file in "$SUBTITLE_DIR"/*.srt; do
    if [ -f "$srt_file" ] && [ "$(basename "$srt_file")" != "subtitles_broken.srt" ]; then
        # Check if file is UTF-8
        CHARSET=$(file -bi "$srt_file" | grep -oP 'charset=\K[^\s]+' || echo "unknown")
        
        if [[ "$CHARSET" == "utf-8" ]] || [[ "$CHARSET" == "us-ascii" ]]; then
            echo "✅ Found UTF-8 subtitle file: $srt_file"
            CONVERTED_FILE_FOUND="true"
            CONVERTED_FILE_PATH="$srt_file"
            
            # Copy the converted file
            cp "$srt_file" /tmp/vlc_subtitle_converted.srt
            break
        fi
    fi
done

# If no converted file found, check if original was modified
if [ "$CONVERTED_FILE_FOUND" = "false" ]; then
    if [ -f "$SUBTITLE_DIR/subtitles_broken.srt" ]; then
        CHARSET=$(file -bi "$SUBTITLE_DIR/subtitles_broken.srt" | grep -oP 'charset=\K[^\s]+' || echo "unknown")
        
        if [[ "$CHARSET" == "utf-8" ]] || [[ "$CHARSET" == "us-ascii" ]]; then
            echo "✅ Original file was converted in-place to UTF-8"
            CONVERTED_FILE_FOUND="true"
            CONVERTED_FILE_PATH="$SUBTITLE_DIR/subtitles_broken.srt"
            cp "$SUBTITLE_DIR/subtitles_broken.srt" /tmp/vlc_subtitle_converted.srt
        fi
    fi
fi

# Check encoding of all subtitle files for verification
find "$SUBTITLE_DIR" -name "*.srt" -exec file -bi {} \; > /tmp/vlc_subtitle_encoding_info.txt 2>/dev/null || echo "No subtitle files" > /tmp/vlc_subtitle_encoding_info.txt

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

# Write result summary JSON
cat > /tmp/vlc_subtitle_encoding_result.json <<EOF
{
    "vlcrc_encoding": "$VLCRC_ENCODING",
    "converted_file_found": $CONVERTED_FILE_FOUND,
    "converted_file_path": "$CONVERTED_FILE_PATH",
    "config_approach": $([ -n "$VLCRC_ENCODING" ] && echo "true" || echo "false"),
    "conversion_approach": $CONVERTED_FILE_FOUND
}
EOF

echo "✅ Result summary saved to /tmp/vlc_subtitle_encoding_result.json"
cat /tmp/vlc_subtitle_encoding_result.json

echo "$(date)" > /tmp/vlc_subtitle_encoding_completed.txt
echo "Subtitle encoding task completed" >> /tmp/vlc_subtitle_encoding_completed.txt

# Export VLC logs
if [ -f /tmp/vlc_subtitle_encoding_task.log ]; then
    cp /tmp/vlc_subtitle_encoding_task.log /tmp/vlc_subtitle_encoding_vlc.log
fi

echo "=== Export Complete ==="