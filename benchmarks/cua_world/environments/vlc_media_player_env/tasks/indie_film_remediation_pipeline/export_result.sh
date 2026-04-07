#!/bin/bash
echo "=== Exporting Indie Film Remediation Pipeline Results ==="

# Record task end time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

MASTERS_DIR="/home/ga/Videos/festival_masters"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Probe Exhibition Master
if [ -f "$MASTERS_DIR/exhibition_master.mkv" ]; then
    EXHIBITION_MTIME=$(stat -c %Y "$MASTERS_DIR/exhibition_master.mkv" 2>/dev/null || echo "0")
    ffprobe -v error -show_format -show_streams -of json "$MASTERS_DIR/exhibition_master.mkv" > /tmp/probe_exhibition.json 2>/dev/null || echo "{}" > /tmp/probe_exhibition.json
    
    # Extract subtitle to verify timing shift
    ffmpeg -y -i "$MASTERS_DIR/exhibition_master.mkv" -map 0:s:0 -f srt /tmp/exhibition_subs.srt 2>/dev/null || true
else
    EXHIBITION_MTIME=0
    echo "{}" > /tmp/probe_exhibition.json
fi

# 2. Probe Hardsub Master
if [ -f "$MASTERS_DIR/hardsub_master.mp4" ]; then
    HARDSUB_MTIME=$(stat -c %Y "$MASTERS_DIR/hardsub_master.mp4" 2>/dev/null || echo "0")
    ffprobe -v error -show_format -show_streams -of json "$MASTERS_DIR/hardsub_master.mp4" > /tmp/probe_hardsub.json 2>/dev/null || echo "{}" > /tmp/probe_hardsub.json
else
    HARDSUB_MTIME=0
    echo "{}" > /tmp/probe_hardsub.json
fi

# 3. Probe Commentary Edition
if [ -f "$MASTERS_DIR/commentary_edition.mkv" ]; then
    COMMENTARY_MTIME=$(stat -c %Y "$MASTERS_DIR/commentary_edition.mkv" 2>/dev/null || echo "0")
    ffprobe -v error -show_format -show_streams -of json "$MASTERS_DIR/commentary_edition.mkv" > /tmp/probe_commentary.json 2>/dev/null || echo "{}" > /tmp/probe_commentary.json
else
    COMMENTARY_MTIME=0
    echo "{}" > /tmp/probe_commentary.json
fi

# 4. Copy Remediation Report
if [ -f "$MASTERS_DIR/remediation_report.json" ]; then
    cp "$MASTERS_DIR/remediation_report.json" /tmp/remediation_report.json 2>/dev/null || true
fi

# Generate metadata export payload
TEMP_META=$(mktemp /tmp/task_meta.XXXXXX.json)
cat > "$TEMP_META" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "exhibition_mtime": $EXHIBITION_MTIME,
    "hardsub_mtime": $HARDSUB_MTIME,
    "commentary_mtime": $COMMENTARY_MTIME
}
EOF

mv "$TEMP_META" /tmp/task_meta.json
chmod 666 /tmp/task_meta.json /tmp/probe_*.json /tmp/exhibition_subs.srt /tmp/remediation_report.json 2>/dev/null || true

echo "=== Export complete ==="