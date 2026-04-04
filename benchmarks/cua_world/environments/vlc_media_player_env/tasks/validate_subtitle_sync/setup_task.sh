#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Validate Subtitle Sync Task ==="

kill_vlc ga
sleep 1

# Ensure directories exist
TASK_DIR="/home/ga/Videos"
SUBTITLE_DIR="$TASK_DIR"
mkdir -p "$TASK_DIR"
mkdir -p /home/ga/Desktop

SETUP_LOG="/tmp/vlc_subtitle_validation_setup.log"

log() {
    echo "[SETUP] $1" | tee -a "$SETUP_LOG"
}

log "Setting up subtitle validation task..."

cd "$TASK_DIR"

# Generate a test video (3 minutes = 180 seconds)
# Use testsrc with some visual variation
log "Generating test video (180 seconds)..."
if [ ! -f "$TASK_DIR/foreign_film.mp4" ]; then
    ffmpeg -f lavfi -i "testsrc=duration=180:size=1280x720:rate=24" \
           -f lavfi -i "sine=frequency=440:duration=180" \
           -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
           -c:a aac -b:a 128k \
           -y "$TASK_DIR/foreign_film.mp4" >> "$SETUP_LOG" 2>&1 || {
        log "ERROR: Failed to generate video"
        exit 1
    }
    log "Video generated successfully"
else
    log "Video already exists, skipping generation"
fi

# Create a matching subtitle file with specific timestamps
log "Creating subtitle file..."
cat > "$SUBTITLE_DIR/foreign_film.srt" << 'EOF'
1
00:00:30,000 --> 00:00:34,000
Opening scene dialogue begins here.
This is the BEGINNING checkpoint.

2
00:00:35,000 --> 00:00:39,000
If you can read this clearly around 35 seconds,
the subtitles are properly synchronized.

3
00:00:45,000 --> 00:00:49,000
The protagonist enters the scene.

4
00:01:28,000 --> 00:01:33,000
This is the MIDDLE checkpoint.
You should see this around 1 minute 30 seconds.

5
00:01:34,000 --> 00:01:38,000
If this appears at the right time,
synchronization is good at the halfway point.

6
00:01:50,000 --> 00:01:54,000
The plot thickens as tensions rise.

7
00:02:20,000 --> 00:02:24,000
Approaching the climax of the story.

8
00:02:50,000 --> 00:02:55,000
This is the NEAR-END checkpoint.
Final validation point before conclusion.

9
00:02:56,000 --> 00:03:00,000
The resolution unfolds as our story concludes.
If you see this at 2:56, sync is excellent!

10
00:03:00,000 --> 00:03:05,000
[The End]
EOF

log "Subtitle file created"

# Get actual video duration for reference
if command -v ffprobe &> /dev/null; then
    DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$TASK_DIR/foreign_film.mp4" 2>/dev/null || echo "180")
    log "Video duration: ${DURATION}s"
else
    log "ffprobe not available, assuming 180s duration"
    DURATION="180"
fi

# Create task instructions file on desktop
cat > /home/ga/Desktop/SUBTITLE_VALIDATION_TASK.txt << EOF
╔══════════════════════════════════════════════════════════════╗
║           SUBTITLE VALIDATION TASK                           ║
╚══════════════════════════════════════════════════════════════╝

VIDEO FILE: /home/ga/Videos/foreign_film.mp4
SUBTITLE FILE: /home/ga/Videos/foreign_film.srt

YOUR MISSION:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Verify that the subtitle file properly matches and synchronizes 
with the video file by checking sync at THREE key checkpoints.

INSTRUCTIONS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. Open VLC (if not already open)

2. Load the video: /home/ga/Videos/foreign_film.mp4
   (Media → Open File, or drag-and-drop)

3. Load the subtitle file: /home/ga/Videos/foreign_film.srt
   (Subtitle → Add Subtitle File...)

4. Verify sync at THREE checkpoints:

   ┌─ CHECKPOINT 1: BEGINNING (0:30 - 0:40) ─────────────┐
   │ Seek to around 30-40 seconds into the video         │
   │ Check: Do subtitles appear and match the timing?    │
   │ Look for: "Opening scene dialogue" or similar       │
   └──────────────────────────────────────────────────────┘

   ┌─ CHECKPOINT 2: MIDDLE (~1:30) ───────────────────────┐
   │ Seek to around 1 minute 30 seconds (halfway point)  │
   │ Check: Do subtitles still appear correctly?          │
   │ Look for: "MIDDLE checkpoint" message                │
   └──────────────────────────────────────────────────────┘

   ┌─ CHECKPOINT 3: NEAR END (~2:50) ─────────────────────┐
   │ Seek to around 2 minutes 50 seconds (near end)      │
   │ Check: Are subtitles still synchronized?             │
   │ Look for: "NEAR-END checkpoint" message              │
   └──────────────────────────────────────────────────────┘

5. Create validation report at:
   /home/ga/subtitle_validation_report.txt

REPORT FORMAT (copy and fill in):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Subtitles Loaded: YES/NO
Video Duration: [duration in seconds, e.g., 180]
Subtitle End Time: [last subtitle timestamp, e.g., 00:03:05]

Checkpoint 1 (0:30-0:40): PASS/FAIL
Checkpoint 2 (Middle ~1:30): PASS/FAIL
Checkpoint 3 (Near End ~2:50): PASS/FAIL

Overall Verdict: PASS/FAIL
Notes: [Any observations about sync quality, timing issues, etc.]

GRADING CRITERIA:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• PASS: Subtitles appear and are reasonably in sync at checkpoint
• FAIL: No subtitles appear OR severely out of sync (>5 seconds off)
• Overall Verdict: PASS only if ALL three checkpoints pass

TIPS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• Use spacebar to pause/play
• Click on progress bar to seek to specific times
• Use Shift+Left/Right arrows to jump 5 seconds
• If subtitles don't appear, check Subtitle menu → Sub Track

Good luck! 🎬
EOF

chown -R ga:ga "$TASK_DIR" /home/ga/Desktop/SUBTITLE_VALIDATION_TASK.txt

# Launch VLC with the video (but don't auto-load subtitles - let agent do it)
log "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show '$TASK_DIR/foreign_film.mp4' > /tmp/vlc_subtitle_validation_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    log "ERROR: VLC failed to start"
    cat /tmp/vlc_subtitle_validation_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    log "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
log "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    log "VLC window focused"
fi

# Pause video so agent can work methodically
sleep 2
log "Pausing video..."
su - ga -c "DISPLAY=:1 xdotool key space" || true
sleep 0.5

log "=== Validate Subtitle Sync Task Setup Complete ==="
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 TASK READY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📂 Video: $TASK_DIR/foreign_film.mp4"
echo "📄 Subtitles: $SUBTITLE_DIR/foreign_film.srt"
echo "📝 Instructions: /home/ga/Desktop/SUBTITLE_VALIDATION_TASK.txt"
echo "🎯 Goal: Create validation report at /home/ga/subtitle_validation_report.txt"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"