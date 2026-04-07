#!/bin/bash
echo "=== Setting up VOIP Phone Audio Package task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/Music/raw_recordings
mkdir -p /home/ga/Music/phone_system
mkdir -p /home/ga/Documents

# Clean up any existing files
rm -f /home/ga/Music/raw_recordings/* 2>/dev/null
rm -f /home/ga/Music/phone_system/* 2>/dev/null

echo "Generating simulated raw audio recordings (44.1kHz Stereo 16-bit)..."

# 1. greeting_main.wav (8 seconds, voice-like bandpass pink noise)
ffmpeg -y -f lavfi -i "anoisesrc=c=pink:r=44100:d=8,lowpass=f=3000,highpass=f=300" -c:a pcm_s16le -ar 44100 -ac 2 /home/ga/Music/raw_recordings/greeting_main.wav 2>/dev/null

# 2. menu_sales.wav (4 seconds)
ffmpeg -y -f lavfi -i "anoisesrc=c=pink:r=44100:d=4,lowpass=f=2500,highpass=f=400" -c:a pcm_s16le -ar 44100 -ac 2 /home/ga/Music/raw_recordings/menu_sales.wav 2>/dev/null

# 3. menu_support.wav (4 seconds)
ffmpeg -y -f lavfi -i "anoisesrc=c=pink:r=44100:d=4,lowpass=f=2600,highpass=f=500" -c:a pcm_s16le -ar 44100 -ac 2 /home/ga/Music/raw_recordings/menu_support.wav 2>/dev/null

# 4. menu_billing.wav (4 seconds)
ffmpeg -y -f lavfi -i "anoisesrc=c=pink:r=44100:d=4,lowpass=f=2700,highpass=f=600" -c:a pcm_s16le -ar 44100 -ac 2 /home/ga/Music/raw_recordings/menu_billing.wav 2>/dev/null

# 5. hold_music.wav (15 seconds, musical tremolo tone)
ffmpeg -y -f lavfi -i "sine=f=440:d=15,tremolo=f=5:d=0.8" -c:a pcm_s16le -ar 44100 -ac 2 /home/ga/Music/raw_recordings/hold_music.wav 2>/dev/null

# 6. voicemail_prompt.wav (5 seconds, voice-like)
ffmpeg -y -f lavfi -i "anoisesrc=c=pink:r=44100:d=5,lowpass=f=3000,highpass=f=300" -c:a pcm_s16le -ar 44100 -ac 2 /home/ga/Music/raw_recordings/voicemail_prompt.wav 2>/dev/null

# Create specifications document
cat > /home/ga/Documents/phone_system_spec.txt << 'EOF'
=== Bright Smile Dental - Phone System Audio Requirements ===

TARGET SYSTEM: Asterisk PBX v18
REQUIRED FORMAT (Strict):
- Format: WAV
- Sample Rate: 8000 Hz
- Channels: Mono (1 channel)
- Bit Depth: 16-bit Signed PCM

DELIVERABLES & INSTRUCTIONS:
All outputs must be saved to /home/ga/Music/phone_system/

1. main_greeting.wav
   - Convert 'greeting_main.wav' to the strict target format.

2. ivr_full_menu.wav
   - Concatenate the following files in this exact sequence:
     greeting_main -> menu_sales -> menu_support -> menu_billing
   - Output must be in the strict target format.

3. hold_music.wav
   - The source 'hold_music.wav' is only ~15s.
   - Loop and trim the audio so the final file is EXACTLY 60 seconds long.
   - Output must be in the strict target format.

4. voicemail.wav
   - Take 'voicemail_prompt.wav'.
   - Append a 1000 Hz beep tone that lasts exactly 0.5 seconds.
   - Append exactly 3.0 seconds of absolute silence after the beep.
   - Output must be in the strict target format.

5. ivr_full_menu.mp3
   - A backup of the ivr_full_menu for the web developer.
   - Format: MP3
   - Bitrate: 64 kbps
   - Channels: Mono

6. manifest.json
   - Create a JSON inventory file describing the 5 audio files created above.
   - Must include an array 'files' containing objects with keys:
     'filename', 'purpose', 'duration_seconds', 'sample_rate', 'channels', and 'format'.

NOTE: The phone system will crash if files are not strictly 8000Hz mono 16-bit PCM WAV.
EOF

# Set permissions
chown -R ga:ga /home/ga/Music /home/ga/Documents

# Launch VLC in background
if ! pgrep -f "vlc" > /dev/null; then
    su - ga -c "DISPLAY=:1 vlc --no-video-title-show &"
    sleep 3
fi

# Maximize and focus VLC
DISPLAY=:1 wmctrl -r "VLC" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "VLC" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="