#!/bin/bash
echo "=== Exporting task results ==="

# Record task timeline
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_DIR="/home/ga/Documents/delivery_package"
SCREENER="$OUTPUT_DIR/scene42_director_screener.mp4"
MIXDOWN="$OUTPUT_DIR/scene42_adr_mixdown.mp3"
MANIFEST="$OUTPUT_DIR/delivery_manifest.json"

# Capture final visual state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Analyze Screener Output
SCREENER_EXISTS="false"
SCREENER_DURATION="0"
SCREENER_WIDTH="0"
SCREENER_HEIGHT="0"
SCREENER_VCODEC="none"
SCREENER_ACODEC="none"
SCREENER_HIGH_FREQ_VOL="-99.0"

if [ -f "$SCREENER" ]; then
    SCREENER_EXISTS="true"
    SCREENER_DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$SCREENER" 2>/dev/null || echo "0")
    SCREENER_WIDTH=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "$SCREENER" 2>/dev/null || echo "0")
    SCREENER_HEIGHT=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$SCREENER" 2>/dev/null || echo "0")
    SCREENER_VCODEC=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$SCREENER" 2>/dev/null || echo "none")
    SCREENER_ACODEC=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$SCREENER" 2>/dev/null || echo "none")
    
    # Check audio frequency profile via high-pass filter. 
    # ADR audio (880Hz) will pass through unaffected (~ -5 dB). Raw audio (440Hz) will be attenuated (< -30 dB).
    VOL_STR=$(ffmpeg -i "$SCREENER" -af "highpass=f=600,volumedetect" -f null - 2>&1 | grep "mean_volume" || echo "mean_volume: -99.0 dB")
    SCREENER_HIGH_FREQ_VOL=$(echo "$VOL_STR" | sed -n 's/.*mean_volume: \([-0-9.]*\).*/\1/p')
    if [ -z "$SCREENER_HIGH_FREQ_VOL" ]; then SCREENER_HIGH_FREQ_VOL="-99.0"; fi
    
    # Extract a central frame for VLM watermark verification
    ffmpeg -y -i "$SCREENER" -ss 00:00:10 -vframes 1 /tmp/screener_frame.png 2>/dev/null
fi

# 2. Analyze Mixdown Output
MIXDOWN_EXISTS="false"
MIXDOWN_DURATION="0"
MIXDOWN_CHANNELS="0"
MIXDOWN_BITRATE="0"
MIXDOWN_ACODEC="none"

if [ -f "$MIXDOWN" ]; then
    MIXDOWN_EXISTS="true"
    MIXDOWN_DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$MIXDOWN" 2>/dev/null || echo "0")
    MIXDOWN_CHANNELS=$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 "$MIXDOWN" 2>/dev/null || echo "0")
    MIXDOWN_BITRATE=$(ffprobe -v error -select_streams a:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 "$MIXDOWN" 2>/dev/null || echo "0")
    MIXDOWN_ACODEC=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$MIXDOWN" 2>/dev/null || echo "none")
fi

# 3. Analyze Manifest
MANIFEST_EXISTS="false"
MANIFEST_VALID="false"
if [ -f "$MANIFEST" ]; then
    MANIFEST_EXISTS="true"
    if jq empty "$MANIFEST" 2>/dev/null; then
        MANIFEST_VALID="true"
    fi
fi

# Package all verification data into a JSON file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screener": {
        "exists": $SCREENER_EXISTS,
        "duration": $SCREENER_DURATION,
        "width": $SCREENER_WIDTH,
        "height": $SCREENER_HEIGHT,
        "vcodec": "$SCREENER_VCODEC",
        "acodec": "$SCREENER_ACODEC",
        "high_freq_vol": $SCREENER_HIGH_FREQ_VOL
    },
    "mixdown": {
        "exists": $MIXDOWN_EXISTS,
        "duration": $MIXDOWN_DURATION,
        "channels": $MIXDOWN_CHANNELS,
        "bitrate": $MIXDOWN_BITRATE,
        "acodec": "$MIXDOWN_ACODEC"
    },
    "manifest": {
        "exists": $MANIFEST_EXISTS,
        "valid": $MANIFEST_VALID
    }
}
EOF

# Move securely out to /tmp
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
echo "=== Export complete ==="