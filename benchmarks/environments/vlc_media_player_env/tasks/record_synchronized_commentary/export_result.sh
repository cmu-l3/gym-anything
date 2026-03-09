#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Record Synchronized Commentary Result ==="

# Check multiple possible locations for recorded audio
SEARCH_DIRS=(
    "/home/ga/Videos/recorded_commentary"
    "/home/ga/Videos"
    "/home/ga/Music"
    "/home/ga"
)

AUDIO_EXTENSIONS=("*.mp3" "*.wav" "*.ogg" "*.m4a" "*.aac" "*.flac")

echo "Searching for recorded audio files..."

FOUND_FILES=()

for dir in "${SEARCH_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        for ext in "${AUDIO_EXTENSIONS[@]}"; do
            # Find files created after task start, with reasonable size
            while IFS= read -r file; do
                if [ -f "$file" ] && [ -s "$file" ]; then
                    SIZE=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
                    # Only consider files >50KB
                    if [ "$SIZE" -gt 51200 ]; then
                        FOUND_FILES+=("$file")
                        echo "  Found: $file ($(du -h "$file" | cut -f1))"
                    fi
                fi
            done < <(find "$dir" -maxdepth 2 -type f -name "$ext" -newer /tmp/task_start_marker 2>/dev/null || true)
        done
    fi
done

# Also search for VLC's default recording pattern
VLC_RECORD_PATTERN="/home/ga/Videos/vlc-record-*.mp3"
for file in $VLC_RECORD_PATTERN; do
    if [ -f "$file" ] && [ -s "$file" ]; then
        SIZE=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
        if [ "$SIZE" -gt 51200 ]; then
            # Check if not already in list
            if [[ ! " ${FOUND_FILES[@]} " =~ " ${file} " ]]; then
                FOUND_FILES+=("$file")
                echo "  Found VLC recording: $file ($(du -h "$file" | cut -f1))"
            fi
        fi
    fi
done

# Select the best candidate (largest file, most likely to be the recording)
BEST_FILE=""
MAX_SIZE=0

for file in "${FOUND_FILES[@]}"; do
    SIZE=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
    if [ "$SIZE" -gt "$MAX_SIZE" ]; then
        MAX_SIZE=$SIZE
        BEST_FILE="$file"
    fi
done

if [ -n "$BEST_FILE" ]; then
    echo ""
    echo "✅ Selected recorded audio: $BEST_FILE"
    echo "   Size: $(du -h "$BEST_FILE" | cut -f1)"
    
    # Copy to standard output location
    cp "$BEST_FILE" /tmp/vlc_recorded_commentary.mp3
    
    # Get audio info using ffprobe if available
    if command -v ffprobe &> /dev/null; then
        echo "   Analyzing audio properties..."
        ffprobe -v error -show_format -show_streams -of json "$BEST_FILE" > /tmp/vlc_recording_info.json 2>&1 || true
        
        # Extract basic info
        DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$BEST_FILE" 2>/dev/null || echo "0")
        CODEC=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$BEST_FILE" 2>/dev/null || echo "unknown")
        
        echo "   Duration: ${DURATION}s"
        echo "   Codec: $CODEC"
    fi
    
    # Create result metadata
    cat > /tmp/vlc_recording_metadata.json <<EOF
{
    "found": true,
    "filepath": "$BEST_FILE",
    "filename": "$(basename "$BEST_FILE")",
    "size_bytes": $MAX_SIZE,
    "size_kb": $(echo "scale=2; $MAX_SIZE / 1024" | bc),
    "duration_sec": ${DURATION:-0},
    "codec": "${CODEC:-unknown}",
    "timestamp": "$(date -Iseconds)"
}
EOF
    
else
    echo ""
    echo "⚠️  No recorded audio file found"
    echo "   Searched in: ${SEARCH_DIRS[*]}"
    echo "   Extensions: ${AUDIO_EXTENSIONS[*]}"
    echo "   Files must be >50KB and created after task start"
    
    # Create empty metadata
    cat > /tmp/vlc_recording_metadata.json <<EOF
{
    "found": false,
    "filepath": "",
    "filename": "",
    "size_bytes": 0,
    "size_kb": 0,
    "duration_sec": 0,
    "codec": "none",
    "timestamp": "$(date -Iseconds)"
}
EOF
fi

# List all audio files for debugging
echo ""
echo "All audio files in Videos directory:"
find /home/ga/Videos -type f \( -name "*.mp3" -o -name "*.wav" -o -name "*.ogg" \) -ls 2>/dev/null || echo "  (none found)"

# Close VLC
if is_vlc_running; then
    echo ""
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force killing VLC..."
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date -Iseconds)" > /tmp/vlc_commentary_completed.txt
echo "Task completed" >> /tmp/vlc_commentary_completed.txt
if [ -n "$BEST_FILE" ]; then
    echo "Recording found: $(basename "$BEST_FILE")" >> /tmp/vlc_commentary_completed.txt
else
    echo "Recording not found" >> /tmp/vlc_commentary_completed.txt
fi

echo ""
echo "=== Export Complete ==="