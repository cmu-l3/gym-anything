#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Expected paths
DIR="/home/ga/Videos/leaderboard_submission"
CLEAN_RUN="$DIR/clean_run.mp4"
RUN_AUDIO="$DIR/run_audio.mp3"
THUMBNAIL="$DIR/victory_thumbnail.png"
MANIFEST="$DIR/manifest.json"

# File stat collector
get_mtime() {
    if [ -f "$1" ]; then stat -c %Y "$1" 2>/dev/null || echo "0"; else echo "0"; fi
}
get_size() {
    if [ -f "$1" ]; then stat -c %s "$1" 2>/dev/null || echo "0"; else echo "0"; fi
}

CLEAN_RUN_MTIME=$(get_mtime "$CLEAN_RUN")
RUN_AUDIO_MTIME=$(get_mtime "$RUN_AUDIO")
THUMBNAIL_MTIME=$(get_mtime "$THUMBNAIL")
MANIFEST_MTIME=$(get_mtime "$MANIFEST")

# Generate JSON probes for media files (so the verifier host doesn't have to copy large video files)
rm -f /tmp/clean_run_probe.json /tmp/run_audio_probe.json

if [ -f "$CLEAN_RUN" ]; then
    ffprobe -v error -show_format -show_streams -of json "$CLEAN_RUN" > /tmp/clean_run_probe.json 2>/dev/null
else
    echo "{}" > /tmp/clean_run_probe.json
fi

if [ -f "$RUN_AUDIO" ]; then
    ffprobe -v error -show_format -show_streams -of json "$RUN_AUDIO" > /tmp/run_audio_probe.json 2>/dev/null
else
    echo "{}" > /tmp/run_audio_probe.json
fi

# Copy the thumbnail and manifest to /tmp/ so copy_from_env can pull them
rm -f /tmp/victory_thumbnail.png /tmp/submission_manifest.json
[ -f "$THUMBNAIL" ] && cp "$THUMBNAIL" /tmp/victory_thumbnail.png
[ -f "$MANIFEST" ] && cp "$MANIFEST" /tmp/submission_manifest.json

# Create main JSON result summary
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "clean_run": {
        "exists": $([ -f "$CLEAN_RUN" ] && echo "true" || echo "false"),
        "mtime": $CLEAN_RUN_MTIME,
        "size": $(get_size "$CLEAN_RUN")
    },
    "run_audio": {
        "exists": $([ -f "$RUN_AUDIO" ] && echo "true" || echo "false"),
        "mtime": $RUN_AUDIO_MTIME,
        "size": $(get_size "$RUN_AUDIO")
    },
    "thumbnail": {
        "exists": $([ -f "$THUMBNAIL" ] && echo "true" || echo "false"),
        "mtime": $THUMBNAIL_MTIME,
        "size": $(get_size "$THUMBNAIL")
    },
    "manifest": {
        "exists": $([ -f "$MANIFEST" ] && echo "true" || echo "false"),
        "mtime": $MANIFEST_MTIME,
        "size": $(get_size "$MANIFEST")
    }
}
EOF

# Make sure all exported files have permissive access for copy_from_env
chmod 666 /tmp/clean_run_probe.json /tmp/run_audio_probe.json /tmp/victory_thumbnail.png /tmp/submission_manifest.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="