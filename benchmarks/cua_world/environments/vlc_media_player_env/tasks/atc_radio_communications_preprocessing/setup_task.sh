#!/bin/bash
# Setup script for atc_radio_communications_preprocessing task
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up ATC Preprocessing Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

kill_vlc 2>/dev/null || true

# Create required directories
mkdir -p /home/ga/Music/processed
mkdir -p /home/ga/Pictures/diagnostics
mkdir -p /home/ga/Documents

echo "Generating raw SDR capture (15 minutes stereo with sparse audio)..."
# We generate a 15-minute (900s) stereo file.
# Left channel (Tower): Active 10-70s, 200-260s, 500-560s (180 seconds total active)
# Right channel (Ground): Active 100-140s, 300-340s, 700-720s (100 seconds total active)
# Background is pink noise at 0.05 amplitude (~ -26dB). Active signals are 0.8 amplitude (~ -2dB).
ffmpeg -y -f lavfi -i "anoisesrc=d=900:c=pink:r=48000:a=0.05" \
  -f lavfi -i "sine=f=500:r=48000:d=900" \
  -f lavfi -i "sine=f=800:r=48000:d=900" \
  -filter_complex "
    [1:a]volume='if(between(t,10,70)+between(t,200,260)+between(t,500,560), 0.8, 0)':eval=frame[tower_voice];
    [2:a]volume='if(between(t,100,140)+between(t,300,340)+between(t,700,720), 0.8, 0)':eval=frame[ground_voice];
    [0:a][tower_voice]amix=inputs=2:duration=first[left_mix];
    [0:a][ground_voice]amix=inputs=2:duration=first[right_mix];
    [left_mix][right_mix]join=inputs=2:channel_layout=stereo[stereo_out]
  " -map "[stereo_out]" -c:a pcm_s16le /home/ga/Music/raw_sdr_capture.wav 2>/dev/null

echo "Creating specification document..."
cat > /home/ga/Documents/preprocessing_spec.txt << 'SPECEOF'
=== ATC AUDIO PREPROCESSING SPECIFICATION ===
Project: Whisper-ATC ML Training Pipeline
Source File: /home/ga/Music/raw_sdr_capture.wav (15 minutes, Stereo, 48kHz)

CHANNEL MAPPING:
- Left Channel: Tower Communications
- Right Channel: Ground Communications

PIPELINE REQUIREMENTS:
1. Channel Separation
   - Split the stereo file into two independent mono streams.

2. Frequency Cleanup
   - Apply a highpass filter at 300Hz to remove wind/rumble.
   - Apply a lowpass filter at 3000Hz to remove SDR static/hiss.

3. Silence Removal
   - Strip dead air from both channels to condense the dataset.
   - Hint: The background static floor is around -26dB. A silence threshold of -15dB to -20dB with a duration of >1 second will cleanly isolate the voice transmissions.

4. Output Format
   - Save Tower to: /home/ga/Music/processed/tower_clean.mp3
   - Save Ground to: /home/ga/Music/processed/ground_clean.mp3
   - Format: MP3 codec, strictly 1 channel (Mono), 16000 Hz sample rate, 64kbps bitrate.

5. Visual Diagnostics
   - Generate a full waveform image for each processed file.
   - Save to: /home/ga/Pictures/diagnostics/tower_waveform.png
   - Save to: /home/ga/Pictures/diagnostics/ground_waveform.png

6. Review Playlist
   - Create a VLC XSPF playlist at: /home/ga/Music/processed/atc_review_playlist.xspf
   - Must contain both processed MP3s.
   - Set the display titles (<title> tags) to exactly: "Tower Comms (Cleaned)" and "Ground Comms (Cleaned)".

7. Processing Report
   - Create a JSON report at: /home/ga/Documents/processing_report.json
   - Required keys: 
     "original_duration_sec": 900
     "tower_final_duration_sec": <duration of tower_clean.mp3>
     "ground_final_duration_sec": <duration of ground_clean.mp3>
SPECEOF

# Fix permissions
chown -R ga:ga /home/ga/Music /home/ga/Pictures /home/ga/Documents

# Take initial screenshot (desktop idle)
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="