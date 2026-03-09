#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Navigate Chapter Markers Task ==="

kill_vlc ga
sleep 1

# Ensure required directories exist
mkdir -p /home/ga/Videos
mkdir -p /home/ga/Pictures/vlc
chown -R ga:ga /home/ga/Videos /home/ga/Pictures/vlc

# Check if documentary already exists (skip generation if present)
DOCUMENTARY="/home/ga/Videos/future_energy_documentary.mp4"

if [ ! -f "$DOCUMENTARY" ] || [ ! -s "$DOCUMENTARY" ]; then
    echo "Generating documentary video with chapters..."
    
    # Generate 6 chapter videos with distinct visual content
    # Use shorter durations for testing (scale down from 90min to ~3min total)
    # Real: 12,18,20,15,15,10 min -> Test: 20,30,30,25,25,20 sec = 150s total
    
    # Chapter 1: Introduction (20 seconds) - Blue background
    ffmpeg -f lavfi -i color=c=blue:s=1280x720:d=20 -vf \
        "drawtext=text='FUTURE ENERGY SOURCES':fontsize=60:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2-50,\
         drawtext=text='Introduction':fontsize=40:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2+50" \
        -r 30 -pix_fmt yuv420p -y /tmp/ch1_intro.mp4 2>/dev/null
    
    # Chapter 2: Solar Power (30 seconds) - Yellow/orange with solar text
    ffmpeg -f lavfi -i color=c=orange:s=1280x720:d=30 -vf \
        "drawtext=text='☀ SOLAR POWER ☀':fontsize=72:fontcolor=yellow:x=(w-text_w)/2:y=(h-text_h)/2-60,\
         drawtext=text='Photovoltaic Technology':fontsize=36:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2+60" \
        -r 30 -pix_fmt yuv420p -y /tmp/ch2_solar.mp4 2>/dev/null
    
    # Chapter 3: Wind Energy (30 seconds) - Light blue with wind turbine text
    ffmpeg -f lavfi -i color=c=lightblue:s=1280x720:d=30 -vf \
        "drawtext=text='🌬 WIND ENERGY 🌬':fontsize=72:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2-60,\
         drawtext=text='Wind Turbine Technology':fontsize=36:fontcolor=darkblue:x=(w-text_w)/2:y=(h-text_h)/2+60" \
        -r 30 -pix_fmt yuv420p -y /tmp/ch3_wind.mp4 2>/dev/null
    
    # Chapter 4: Hydroelectric (25 seconds) - Cyan
    ffmpeg -f lavfi -i color=c=cyan:s=1280x720:d=25 -vf \
        "drawtext=text='💧 HYDROELECTRIC 💧':fontsize=60:fontcolor=blue:x=(w-text_w)/2:y=(h-text_h)/2" \
        -r 30 -pix_fmt yuv420p -y /tmp/ch4_hydro.mp4 2>/dev/null
    
    # Chapter 5: Nuclear (25 seconds) - Green
    ffmpeg -f lavfi -i color=c=green:s=1280x720:d=25 -vf \
        "drawtext=text='⚛ NUCLEAR OPTIONS ⚛':fontsize=60:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2" \
        -r 30 -pix_fmt yuv420p -y /tmp/ch5_nuclear.mp4 2>/dev/null
    
    # Chapter 6: Conclusion (20 seconds) - Purple
    ffmpeg -f lavfi -i color=c=purple:s=1280x720:d=20 -vf \
        "drawtext=text='CONCLUSION':fontsize=72:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2" \
        -r 30 -pix_fmt yuv420p -y /tmp/ch6_conclusion.mp4 2>/dev/null
    
    # Concatenate all chapters
    cat > /tmp/concat_list.txt << 'EOF'
file '/tmp/ch1_intro.mp4'
file '/tmp/ch2_solar.mp4'
file '/tmp/ch3_wind.mp4'
file '/tmp/ch4_hydro.mp4'
file '/tmp/ch5_nuclear.mp4'
file '/tmp/ch6_conclusion.mp4'
EOF
    
    ffmpeg -f concat -safe 0 -i /tmp/concat_list.txt -c copy -y /tmp/full_documentary.mp4 2>/dev/null
    
    # Add chapter metadata
    # Using scaled timestamps: 0, 20, 50, 80, 105, 130, 150 seconds
    cat > /tmp/chapters.txt << 'EOF'
;FFMETADATA1
[CHAPTER]
TIMEBASE=1/1000
START=0
END=20000
title=Introduction

[CHAPTER]
TIMEBASE=1/1000
START=20000
END=50000
title=Solar Power

[CHAPTER]
TIMEBASE=1/1000
START=50000
END=80000
title=Wind Energy

[CHAPTER]
TIMEBASE=1/1000
START=80000
END=105000
title=Hydroelectric

[CHAPTER]
TIMEBASE=1/1000
START=105000
END=130000
title=Nuclear Options

[CHAPTER]
TIMEBASE=1/1000
START=130000
END=150000
title=Conclusion
EOF
    
    # Embed chapter metadata
    ffmpeg -i /tmp/full_documentary.mp4 -i /tmp/chapters.txt \
        -map_metadata 1 -codec copy -y "$DOCUMENTARY" 2>/dev/null
    
    # Set ownership
    chown ga:ga "$DOCUMENTARY"
    
    # Clean up temp files
    rm -f /tmp/ch*.mp4 /tmp/full_documentary.mp4 /tmp/concat_list.txt /tmp/chapters.txt
    
    echo "✓ Documentary video with chapters created"
else
    echo "✓ Documentary video already exists, skipping generation"
fi

# Verify video has chapters
if command -v ffprobe &> /dev/null; then
    CHAPTER_COUNT=$(ffprobe -v error -show_chapters "$DOCUMENTARY" 2>/dev/null | grep -c "^\[CHAPTER\]" || echo "0")
    echo "Video has $CHAPTER_COUNT chapters"
fi

# Clear any old snapshots
rm -f /home/ga/Pictures/vlc/solar_power.png
rm -f /home/ga/Pictures/vlc/wind_energy.png
rm -f /home/ga/Pictures/vlc/vlc-snap*.png

# Launch VLC with the documentary
echo "Launching VLC with documentary..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show '$DOCUMENTARY' > /tmp/vlc_chapter_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_chapter_task.log
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

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Pause video to allow agent to navigate
sleep 2
echo "Pausing video..."
su - ga -c "DISPLAY=:1 xdotool key space" || true
sleep 1

echo "=== Navigate Chapter Markers Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Video: /home/ga/Videos/future_energy_documentary.mp4"
echo "  2. Open chapter menu: Playback → Chapter"
echo "  3. Navigate to 'Solar Power' chapter"
echo "  4. Take snapshot: Shift+S"
echo "  5. Rename snapshot to: /home/ga/Pictures/vlc/solar_power.png"
echo "  6. Navigate to 'Wind Energy' chapter"
echo "  7. Take snapshot: Shift+S"
echo "  8. Rename snapshot to: /home/ga/Pictures/vlc/wind_energy.png"
echo ""
echo "Chapters available:"
echo "  1. Introduction (0-20s)"
echo "  2. Solar Power (20-50s) ← TARGET"
echo "  3. Wind Energy (50-80s) ← TARGET"
echo "  4. Hydroelectric (80-105s)"
echo "  5. Nuclear Options (105-130s)"
echo "  6. Conclusion (130-150s)"