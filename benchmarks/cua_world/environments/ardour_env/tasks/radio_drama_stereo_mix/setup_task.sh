#!/bin/bash
echo "=== Setting up Radio Drama Stereo Mix task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Kill any running Ardour instance to start fresh
kill_ardour
sleep 2

# Create working directories
su - ga -c "mkdir -p /home/ga/Audio/radio_drama"
su - ga -c "mkdir -p /home/ga/Audio/radio_drama_mix"
rm -f /home/ga/Audio/radio_drama_mix/*.wav 2>/dev/null || true

# ============================================================
# Prepare audio files from real public-domain recordings
# ============================================================
echo "=== Preparing radio drama audio files ==="

SRC_NARRATION=""
for f in /home/ga/Audio/samples/narration.wav /home/ga/Audio/samples/good_morning.wav /home/ga/Audio/import_me.wav; do
    if [ -f "$f" ] && [ -s "$f" ]; then
        SRC_NARRATION="$f"
        break
    fi
done

SRC_MUSIC=""
for f in /home/ga/Audio/samples/moonlight_sonata.wav /home/ga/Audio/samples/*.wav; do
    if [ -f "$f" ] && [ -s "$f" ] && [ "$f" != "$SRC_NARRATION" ]; then
        SRC_MUSIC="$f"
        break
    fi
done

# Generate audio files using sox/ffmpeg
if [ -n "$SRC_NARRATION" ]; then
    # Narrator intro: first 15 seconds, mono
    sox "$SRC_NARRATION" /home/ga/Audio/radio_drama/narrator_intro.wav trim 0 15 channels 1 rate 44100 2>/dev/null || \
    ffmpeg -y -i "$SRC_NARRATION" -t 15 -ac 1 -ar 44100 /home/ga/Audio/radio_drama/narrator_intro.wav 2>/dev/null || true

    # Character Alice: seconds 3-13, pitch shifted up 2 semitones
    sox "$SRC_NARRATION" /home/ga/Audio/radio_drama/character_alice.wav trim 3 10 channels 1 rate 44100 pitch 200 2>/dev/null || \
    ffmpeg -y -i "$SRC_NARRATION" -ss 3 -t 10 -ac 1 -ar 44100 -af "asetrate=44100*1.122,aresample=44100" /home/ga/Audio/radio_drama/character_alice.wav 2>/dev/null || true

    # Character Bob: seconds 10-20, pitch shifted down 3 semitones
    sox "$SRC_NARRATION" /home/ga/Audio/radio_drama/character_bob.wav trim 10 10 channels 1 rate 44100 pitch -300 2>/dev/null || \
    ffmpeg -y -i "$SRC_NARRATION" -ss 10 -t 10 -ac 1 -ar 44100 -af "asetrate=44100*0.841,aresample=44100" /home/ga/Audio/radio_drama/character_bob.wav 2>/dev/null || true
else
    echo "WARNING: No narration source found, generating synthetically"
    sox -n /home/ga/Audio/radio_drama/narrator_intro.wav synth 15 sine 220 rate 44100 channels 1 2>/dev/null || true
    sox -n /home/ga/Audio/radio_drama/character_alice.wav synth 10 sine 330 rate 44100 channels 1 2>/dev/null || true
    sox -n /home/ga/Audio/radio_drama/character_bob.wav synth 10 sine 165 rate 44100 channels 1 2>/dev/null || true
fi

# Ambience/Room tone: from music source, low-pass filtered heavily
if [ -n "$SRC_MUSIC" ]; then
    sox "$SRC_MUSIC" /home/ga/Audio/radio_drama/ambience_room.wav trim 5 10 rate 44100 lowpass 400 2>/dev/null || \
    ffmpeg -y -i "$SRC_MUSIC" -ss 5 -t 10 -ar 44100 -af "lowpass=f=400" /home/ga/Audio/radio_drama/ambience_room.wav 2>/dev/null || true
else
    # Generate pink noise as room tone
    sox -n /home/ga/Audio/radio_drama/ambience_room.wav synth 10 pinknoise vol 0.3 rate 44100 channels 1 2>/dev/null || true
fi

# Verify audio files were created
echo "Audio files created:"
ls -la /home/ga/Audio/radio_drama/*.wav 2>/dev/null || echo "WARNING: No audio files created!"

# ============================================================
# Create production brief
# ============================================================
cat > /home/ga/Audio/radio_drama/production_brief.txt << 'EOF'
=================================================================
RADIO DRAMA PRODUCTION BRIEF
Cornerstone Community Players — "The Garden Path" Episode 1
Sound Designer: [Your Name]
Date: 2024-11-15
=================================================================

MIXING SPECIFICATIONS
---------------------

Please set up the following four audio tracks in the Ardour session
"MyProject" with the exact specifications below.

Track Layout:

  1. Track Name: "Narrator"
     Audio File:  narrator_intro.wav
     Pan:         Center
     Gain:        0 dB (unity)
     Mute:        No

  2. Track Name: "Alice"
     Audio File:  character_alice.wav
     Pan:         Fully Left (L100)
     Gain:        -3 dB
     Mute:        No

  3. Track Name: "Bob"
     Audio File:  character_bob.wav
     Pan:         Fully Right (R100)
     Gain:        -3 dB
     Mute:        No

  4. Track Name: "Room Tone"
     Audio File:  ambience_room.wav
     Pan:         Center
     Gain:        -15 dB
     Mute:        YES (placeholder — do not include in mix)

SCENE MARKERS
-------------
Place at least three location markers at the following scene boundaries:
  - "Scene 1 - Kitchen"   (near the beginning of the timeline)
  - "Scene 2 - Garden"    (approximately mid-session)
  - "Scene 3 - Finale"    (toward the end of the audio)

DELIVERY
--------
Export the final stereo mix as a WAV file to:
  /home/ga/Audio/radio_drama_mix/

Make sure to save the session after all changes.

=================================================================
EOF

# Ensure permissions are correct
chown -R ga:ga /home/ga/Audio/radio_drama
chown -R ga:ga /home/ga/Audio/radio_drama_mix

# ============================================================
# Clean up existing session files, restore base session
# ============================================================
SESSION_DIR="/home/ga/Audio/sessions/MyProject"
SESSION_FILE="$SESSION_DIR/MyProject.ardour"

if [ ! -f "$SESSION_FILE" ]; then
    echo "ERROR: Base Ardour session not found at $SESSION_FILE"
else
    # Remove any existing exports
    rm -rf "$SESSION_DIR/export"/* 2>/dev/null || true
fi

# Launch Ardour with the existing session
echo "=== Launching Ardour with MyProject session ==="
launch_ardour_session "$SESSION_FILE"
sleep 4

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Radio Drama Stereo Mix task setup complete ==="
echo "Production brief: /home/ga/Audio/radio_drama/production_brief.txt"