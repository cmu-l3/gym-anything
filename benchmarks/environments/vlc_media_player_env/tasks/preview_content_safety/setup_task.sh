#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Preview Content Safety Task ==="

kill_vlc ga
sleep 1

# Ensure directories exist
mkdir -p /home/ga/Videos
mkdir -p /home/ga/Desktop
mkdir -p /tmp/task_data

# Generate 12-minute (720 second) educational video with content warnings at specific timestamps
# The video will show text overlays indicating problematic sections that need to be flagged
echo "Generating educational video with content warnings..."

SCRIPT_DIR="/workspace/tasks/preview_content_safety"

# Create a more visually interesting video with different colored sections
# Blue for normal content, red backgrounds for problematic sections
ffmpeg -y -f lavfi -i "color=c=darkblue:s=1280x720:d=720:r=30" \
  -f lavfi -i "color=c=darkred:s=1280x720:d=30:r=30" \
  -f lavfi -i "color=c=darkred:s=1280x720:d=45:r=30" \
  -f lavfi -i "color=c=darkred:s=1280x720:d=30:r=30" \
  -filter_complex "
    [0:v]drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='World War II Documentary':fontsize=60:fontcolor=white:x=(w-text_w)/2:y=100:enable='between(t,0,60)',
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='Introduction and Historical Context':fontsize=40:fontcolor=white:x=(w-text_w)/2:y=300:enable='between(t,0,60)',
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='Timestamp\: 0\:00':fontsize=30:fontcolor=yellow:x=50:y=650:enable='between(t,0,60)',
    
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='Pre-War Political Climate':fontsize=48:fontcolor=white:x=(w-text_w)/2:y=300:enable='between(t,60,150)',
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='Timestamp\: 1\:00-2\:30':fontsize=30:fontcolor=yellow:x=50:y=650:enable='between(t,60,150)',
    
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='WARNING\: GRAPHIC BATTLE FOOTAGE':fontsize=56:fontcolor=red:box=1:boxcolor=black@0.8:boxborderw=10:x=(w-text_w)/2:y=250:enable='between(t,165,195)',
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='Combat scenes - Violence depicted':fontsize=36:fontcolor=white:x=(w-text_w)/2:y=400:enable='between(t,165,195)',
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='Timestamp\: 2\:45-3\:15':fontsize=32:fontcolor=yellow:x=50:y=650:enable='between(t,165,195)',
    
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='Military Strategy Analysis':fontsize=48:fontcolor=white:x=(w-text_w)/2:y=300:enable='between(t,195,360)',
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='Timestamp\: 3\:15-6\:00':fontsize=30:fontcolor=yellow:x=50:y=650:enable='between(t,195,360)',
    
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='WARNING\: DISTURBING IMAGERY':fontsize=56:fontcolor=red:box=1:boxcolor=black@0.8:boxborderw=10:x=(w-text_w)/2:y=200:enable='between(t,375,420)',
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='Holocaust and concentration camp footage':fontsize=36:fontcolor=white:x=(w-text_w)/2:y=350:enable='between(t,375,420)',
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='May be emotionally distressing for young viewers':fontsize=30:fontcolor=white:x=(w-text_w)/2:y=450:enable='between(t,375,420)',
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='Timestamp\: 6\:15-7\:00':fontsize=32:fontcolor=yellow:x=50:y=650:enable='between(t,375,420)',
    
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='War Impact on Civilians':fontsize=48:fontcolor=white:x=(w-text_w)/2:y=300:enable='between(t,420,630)',
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='Timestamp\: 7\:00-10\:30':fontsize=30:fontcolor=yellow:x=50:y=650:enable='between(t,420,630)',
    
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='WARNING\: MATURE LANGUAGE':fontsize=56:fontcolor=red:box=1:boxcolor=black@0.8:boxborderw=10:x=(w-text_w)/2:y=250:enable='between(t,645,675)',
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='Veteran interviews contain strong language':fontsize=36:fontcolor=white:x=(w-text_w)/2:y=400:enable='between(t,645,675)',
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='Timestamp\: 10\:45-11\:15':fontsize=32:fontcolor=yellow:x=50:y=650:enable='between(t,645,675)',
    
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='Conclusion and Remembrance':fontsize=48:fontcolor=white:x=(w-text_w)/2:y=300:enable='between(t,675,720)',
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='Timestamp\: 11\:15-12\:00':fontsize=30:fontcolor=yellow:x=50:y=650:enable='between(t,675,720)'
    [base];
    [1:v]drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='GRAPHIC CONTENT':fontsize=70:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2[warning1];
    [2:v]drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='DISTURBING IMAGERY':fontsize=70:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2[warning2];
    [3:v]drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='MATURE CONTENT':fontsize=70:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2[warning3];
    [base][warning1]overlay=0:0:enable='between(t,165,195)'[tmp1];
    [tmp1][warning2]overlay=0:0:enable='between(t,375,420)'[tmp2];
    [tmp2][warning3]overlay=0:0:enable='between(t,645,675)'[final]
  " \
  -map "[final]" -c:v libx264 -preset ultrafast -pix_fmt yuv420p -crf 28 \
  /home/ga/Videos/wwii_doc_final_v3.mp4 2>&1 | tee /tmp/ffmpeg_preview.log

if [ ! -f /home/ga/Videos/wwii_doc_final_v3.mp4 ]; then
    echo "ERROR: Failed to create video file"
    cat /tmp/ffmpeg_preview.log
    exit 1
fi

echo "✅ Created test video ($(du -h /home/ga/Videos/wwii_doc_final_v3.mp4 | cut -f1)) with flagged content at:"
echo "  - 2:45-3:15 (165-195s) - Graphic battle footage"
echo "  - 6:15-7:00 (375-420s) - Disturbing concentration camp imagery"
echo "  - 10:45-11:15 (645-675s) - Mature language in interviews"

# Create task instruction file on desktop
cat > /home/ga/Desktop/CONTENT_PREVIEW_TASK.txt << 'EOF'
═══════════════════════════════════════════════════════════
                   CONTENT PREVIEW TASK
═══════════════════════════════════════════════════════════

SCENARIO:
You are a middle school teacher preparing for tomorrow's history class.
A colleague recommended this documentary about World War II, but you need
to preview it first to check for inappropriate content for 12-14 year olds.

You have limited time before a meeting, so you need to preview efficiently.

═══════════════════════════════════════════════════════════

VIDEO TO REVIEW:
  /home/ga/Videos/wwii_doc_final_v3.mp4
  (12 minutes long)

YOUR TASK:
  1. Open the video in VLC
  2. Set playback speed to 1.5x or 2.0x for faster preview
     (Use Playback → Speed menu or press ] key)
  3. Watch for sections with red warnings/problematic content
  4. Note down timestamps of concerning sections
  5. Create review notes file with your findings

═══════════════════════════════════════════════════════════

DELIVERABLE:
Create a text file: /home/ga/Videos/content_review_notes.txt

Required format:
---------------
CONTENT REVIEW NOTES
Video: wwii_doc_final_v3.mp4
Reviewed at: [X.X]x playback speed

FLAGGED SECTIONS:
- MM:SS - [brief description of concern]
- MM:SS - [brief description of concern]
- MM:SS - [brief description of concern]

RECOMMENDATION: [APPROVED / NEEDS EDITING / DO NOT USE]

NOTES: [Any additional comments about the video]
---------------

TIPS:
- Press ] to increase playback speed
- Press [ to decrease playback speed  
- Press = to return to normal speed
- Press Space to pause/resume
- Look for red text warnings in the video

═══════════════════════════════════════════════════════════
EOF

# Set permissions
chown -R ga:ga /home/ga/Videos /home/ga/Desktop

# Launch VLC (not auto-playing - agent needs to open the video)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_preview_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_preview_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    cat /tmp/vlc_preview_task.log
    exit 1
fi

# Click on center of the screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 640 360 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 1
fi

echo "=== Preview Content Safety Task Setup Complete ==="
echo ""
echo "📋 TASK INSTRUCTIONS:"
echo "════════════════════════════════════════════════════════"
echo "  📹 Video: /home/ga/Videos/wwii_doc_final_v3.mp4"
echo "  ⏱️  Duration: 12 minutes"
echo "  🎯 Goal: Preview at faster speed and document concerns"
echo ""
echo "  STEPS:"
echo "  1. Open video file in VLC (Media → Open File)"
echo "  2. Increase playback speed (press ] or Playback → Speed)"
echo "  3. Watch for RED WARNING TEXT at problematic sections"
echo "  4. Note timestamps of flagged content (look for yellow timestamps)"
echo "  5. Create /home/ga/Videos/content_review_notes.txt with:"
echo "     - At least 2-3 flagged timestamps (MM:SS format)"
echo "     - Brief descriptions of concerns"
echo "     - Overall recommendation"
echo ""
echo "  📄 See /home/ga/Desktop/CONTENT_PREVIEW_TASK.txt for details"
echo "════════════════════════════════════════════════════════"