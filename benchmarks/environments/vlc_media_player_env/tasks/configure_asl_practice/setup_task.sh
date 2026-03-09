#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure ASL Practice Task ==="

kill_vlc ga
sleep 1

# Ensure directories exist
mkdir -p /home/ga/Videos
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/.config/vlc

# Reset VLC configuration to defaults for this task
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    # Reset playback speed to default
    sed -i '/^rate=/d' "$VLC_RC"
    sed -i '/^playback-speed=/d' "$VLC_RC"
    
    # Reset any custom hotkeys for frame stepping
    sed -i '/^key-frame-next=/d' "$VLC_RC"
    sed -i '/^key-frame-prev=/d' "$VLC_RC"
    sed -i '/^global-key-frame-next=/d' "$VLC_RC"
    sed -i '/^global-key-frame-prev=/d' "$VLC_RC"
    
    # Reset loop settings
    sed -i '/^loop-a=/d' "$VLC_RC"
    sed -i '/^loop-b=/d' "$VLC_RC"
    sed -i '/^ab-loop-a=/d' "$VLC_RC"
    sed -i '/^ab-loop-b=/d' "$VLC_RC"
    
    echo "VLC config reset to defaults"
fi

# Generate ASL tutorial video (25 minutes for practicality, with clear timestamp markers)
# This simulates a sign language instruction video
OUTPUT_FILE="/home/ga/Videos/asl_tutorial.mp4"

echo "Generating ASL tutorial video (this may take a moment)..."

# Create a 25-minute video with visual timestamp markers at key practice points
ffmpeg -f lavfi -i color=c=darkblue:s=1280x720:d=1500 \
  -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:\
text='ASL Vocabulary Tutorial':fontcolor=white:fontsize=56:x=(w-text_w)/2:y=80,\
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:\
text='Practice Signs':fontcolor=lightblue:fontsize=40:x=(w-text_w)/2:y=200,\
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:\
text='2\\:15 - understand  |  5\\:47 - practice  |  9\\:23 - help':fontcolor=yellow:fontsize=26:x=(w-text_w)/2:y=320,\
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:\
text='15\\:08 - friend  |  21\\:34 - meeting':fontcolor=yellow:fontsize=26:x=(w-text_w)/2:y=370,\
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:\
text='Configure VLC for slow-motion practice (65%% speed)':fontcolor=white:fontsize=28:x=(w-text_w)/2:y=480,\
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:\
text='Duration\\: 25 minutes':fontcolor=gray:fontsize=22:x=(w-text_w)/2:y=580,\
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:\
text='%{pts\\:hms}':fontcolor=lightgreen:fontsize=48:x=(w-text_w)/2:y=650" \
  -c:v libx264 -preset ultrafast -crf 30 -t 1500 -y "$OUTPUT_FILE" 2>/dev/null || {
    echo "Warning: Could not generate full video, creating short version"
    # Fallback to shorter video if generation fails
    ffmpeg -f lavfi -i color=c=darkblue:s=1280x720:d=300 \
      -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:\
text='ASL Tutorial (5min sample)':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=300" \
      -c:v libx264 -preset ultrafast -crf 30 -t 300 -y "$OUTPUT_FILE" 2>/dev/null
}

chown ga:ga "$OUTPUT_FILE"
chmod 644 "$OUTPUT_FILE"

echo "✓ Created ASL tutorial video: $OUTPUT_FILE"

# Create detailed task instructions on desktop
cat > /home/ga/Desktop/ASL_PRACTICE_INSTRUCTIONS.txt << 'EOF'
╔════════════════════════════════════════════════════════════════════════╗
║       TASK: Configure VLC for ASL (Sign Language) Practice Workflow    ║
╚════════════════════════════════════════════════════════════════════════╝

CONTEXT:
You're learning American Sign Language (ASL) from video tutorials.
Sign language requires seeing precise hand shapes, finger positions, and
smooth motion paths. Normal playback is too fast to catch these details!

YOUR MISSION:
Configure VLC to create an optimal sign language learning environment.

═══════════════════════════════════════════════════════════════════════════

REQUIRED CONFIGURATIONS:

1️⃣  SET DEFAULT PLAYBACK SPEED TO 65% (0.65x)
   → Goal: All videos play slower by default for clarity
   → Steps:
     a) Open: Tools → Preferences (or press Ctrl+P)
     b) Click "Show settings: All" at bottom-left (if in Simple mode)
     c) Navigate to: Input / Codecs → Other codecs
     d) Find "Playback speed" setting
     e) Set value to: 0.65 (or 65%)
     
   Alternative method:
     a) Play the video
     b) Go to: Playback → Speed → Custom
     c) Enter: 0.65 or 65%
     d) Make it default in preferences

2️⃣  CONFIGURE FRAME-STEP HOTKEYS
   → Goal: Easy frame-by-frame examination of hand positions
   → Steps:
     a) Open: Tools → Preferences
     b) Select "Hotkeys" from left menu (or click "Show settings: All")
     c) Find "Next frame" action
     d) Double-click and assign key: E (or any easy key)
     e) Find "Previous frame" action  
     f) Assign key: W (or any easy key)
     g) Click "Save"

3️⃣  CREATE 5 BOOKMARKS at practice timestamps
   → Goal: Quick navigation to vocabulary signs
   → Target timestamps:
     • 2:15  (135s) - Sign: "understand"
     • 5:47  (347s) - Sign: "practice"
     • 9:23  (563s) - Sign: "help"
     • 15:08 (908s) - Sign: "friend"
     • 21:34 (1294s) - Sign: "meeting"
   
   → Method 1 - Custom Bookmarks:
     a) Play video and seek to 2:15
     b) Go to: Playback → Custom Bookmarks → Manage
     c) Click "Create" to add bookmark
     d) Repeat for all 5 timestamps
   
   → Method 2 - Create Playlist with markers:
     a) Create new playlist
     b) Add the video 5 times with different start times
     c) Save as: /home/ga/Videos/asl_bookmarks.m3u or .xspf

4️⃣  SET UP A-B LOOP (2:15 to 2:18)
   → Goal: Repeat first sign automatically for practice
   → Steps:
     a) Seek to 2:15 (135 seconds)
     b) Go to: Playback → A→B → Set Point A (or press Shift+L)
     c) Seek to 2:18 (138 seconds)  
     d) Set Point B (press Shift+L again)
     e) Video should now loop between these points

5️⃣  VERIFY SETTINGS PERSIST
   → Close VLC and reopen to ensure settings saved
   → Settings stored in: /home/ga/.config/vlc/vlcrc

═══════════════════════════════════════════════════════════════════════════

VIDEO LOCATION: /home/ga/Videos/asl_tutorial.mp4

IMPORTANT TIPS:
• Use "Show settings: All" for advanced preferences access
• Frame stepping only works when video is PAUSED
• Bookmarks may require VLC restart to persist
• A-B loop can be toggled with Playback → A→B → Loop
• Test by closing and reopening VLC

VERIFICATION SCORING:
✓ Playback speed 60-70%:  40 points
✓ Frame-step hotkeys set:  20 points  
✓ 5 bookmarks created:     30 points
✓ A-B loop configured:     10 points
────────────────────────────────
Minimum passing: 70/100 points

Good luck! 🤟
EOF

chown ga:ga /home/ga/Desktop/ASL_PRACTICE_INSTRUCTIONS.txt
chmod 644 /home/ga/Desktop/ASL_PRACTICE_INSTRUCTIONS.txt

echo "✓ Created task instructions on Desktop"

# Launch VLC with the ASL tutorial video
echo "Launching VLC with ASL tutorial..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show /home/ga/Videos/asl_tutorial.mp4 > /tmp/vlc_asl_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Pause the video so agent can work on configuration
sleep 2
echo "Pausing video..."
su - ga -c "DISPLAY=:1 xdotool key space" || true

echo "=== Configure ASL Practice Task Setup Complete ==="
echo ""
echo "📝 Task Summary:"
echo "  1. Set playback speed to 65% (0.65x)"
echo "  2. Configure frame-step hotkeys (e.g., E/W)"
echo "  3. Create 5 bookmarks at: 2:15, 5:47, 9:23, 15:08, 21:34"
echo "  4. Set A-B loop from 2:15 to 2:18"
echo "  5. Ensure settings persist (saved to vlcrc)"
echo ""
echo "📄 See full instructions: /home/ga/Desktop/ASL_PRACTICE_INSTRUCTIONS.txt"