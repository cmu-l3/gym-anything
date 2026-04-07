#!/bin/bash
# Export script for gallery_video_installation_prep task
set -e

echo "=== Exporting gallery_video_installation_prep results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON export file
JSON_OUT="/tmp/gallery_export.json"
echo "{" > "$JSON_OUT"
echo "  \"task_start\": $TASK_START," >> "$JSON_OUT"
echo "  \"task_end\": $TASK_END," >> "$JSON_OUT"
echo "  \"files\": {" >> "$JSON_OUT"

# Define expected files
EXPECTED_FILES=("room_a_main_hall.mp4" "room_b_quiet_gallery.mp4" "room_c_tower_alcove.mp4" "room_d_lobby_screen.mp4")

FIRST=true
for f in "${EXPECTED_FILES[@]}"; do
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        echo "," >> "$JSON_OUT"
    fi

    # Locate the file (check correct dir first, then fallbacks)
    FOUND_PATH=""
    for DIR in "/home/ga/Videos/gallery_ready" "/home/ga/Videos" "/home/ga/Documents" "/home/ga"; do
        if [ -f "$DIR/$f" ]; then
            FOUND_PATH="$DIR/$f"
            break
        fi
    done

    if [ -n "$FOUND_PATH" ]; then
        MTIME=$(stat -c %Y "$FOUND_PATH" 2>/dev/null || echo "0")
        SIZE=$(stat -c %s "$FOUND_PATH" 2>/dev/null || echo "0")
        
        # Use ffprobe to get video and audio stream details
        V_PROBE=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height -of json "$FOUND_PATH" 2>/dev/null || echo "{}")
        A_PROBE=$(ffprobe -v error -select_streams a -show_entries stream=codec_type -of json "$FOUND_PATH" 2>/dev/null || echo "{}")

        echo "    \"$f\": {" >> "$JSON_OUT"
        echo "      \"exists\": true," >> "$JSON_OUT"
        echo "      \"path\": \"$FOUND_PATH\"," >> "$JSON_OUT"
        echo "      \"mtime\": $MTIME," >> "$JSON_OUT"
        echo "      \"size\": $SIZE," >> "$JSON_OUT"
        echo "      \"video_info\": $V_PROBE," >> "$JSON_OUT"
        echo "      \"audio_info\": $A_PROBE" >> "$JSON_OUT"
        echo "    }" >> "$JSON_OUT"
    else
        echo "    \"$f\": {\"exists\": false}" >> "$JSON_OUT"
    fi
done

echo "  }," >> "$JSON_OUT"

# Check for M3U Playlist
M3U_PATH="/home/ga/Videos/gallery_ready/installation_test.m3u"
if [ ! -f "$M3U_PATH" ]; then
    M3U_PATH=$(find /home/ga -name "installation_test.m3u" 2>/dev/null | head -1)
fi

if [ -n "$M3U_PATH" ] && [ -f "$M3U_PATH" ]; then
    cp "$M3U_PATH" /tmp/installation_test.m3u
    echo "  \"m3u_exists\": true," >> "$JSON_OUT"
else
    echo "  \"m3u_exists\": false," >> "$JSON_OUT"
fi

# Check for JSON Manifest
MANIFEST_PATH="/home/ga/Documents/installation_manifest.json"
if [ ! -f "$MANIFEST_PATH" ]; then
    MANIFEST_PATH=$(find /home/ga -name "installation_manifest.json" 2>/dev/null | head -1)
fi

if [ -n "$MANIFEST_PATH" ] && [ -f "$MANIFEST_PATH" ]; then
    cp "$MANIFEST_PATH" /tmp/installation_manifest.json
    echo "  \"manifest_exists\": true" >> "$JSON_OUT"
else
    echo "  \"manifest_exists\": false" >> "$JSON_OUT"
fi

echo "}" >> "$JSON_OUT"

chmod 666 /tmp/gallery_export.json 2>/dev/null || true
if [ -f /tmp/installation_test.m3u ]; then chmod 666 /tmp/installation_test.m3u 2>/dev/null || true; fi
if [ -f /tmp/installation_manifest.json ]; then chmod 666 /tmp/installation_manifest.json 2>/dev/null || true; fi

# Kill VLC
pkill -f "vlc" 2>/dev/null || true

echo "=== Export complete ==="