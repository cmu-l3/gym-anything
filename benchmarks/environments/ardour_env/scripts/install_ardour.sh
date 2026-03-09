#!/bin/bash
set -e

echo "=== Installing Ardour DAW ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install Ardour and audio dependencies
apt-get install -y \
    ardour \
    jackd2 \
    alsa-utils \
    pulseaudio \
    ffmpeg \
    sox \
    libsox-fmt-all \
    lame \
    vorbis-tools \
    libcanberra-gtk-module

# Install GUI automation and utility tools
apt-get install -y \
    xdotool \
    wmctrl \
    scrot \
    x11-utils \
    xclip \
    python3-pip

# Install Python libraries for verification
pip3 install --break-system-packages pillow numpy 2>/dev/null || \
pip3 install pillow numpy 2>/dev/null || true

# Add ga user to audio group (needed for JACK/ALSA access)
usermod -aG audio ga 2>/dev/null || true

# Download real public domain audio files from Internet Archive
echo "=== Downloading real audio data ==="
mkdir -p /home/ga/Audio/samples

# 1. Beethoven Moonlight Sonata (real classical music, public domain)
wget -q --timeout=60 --tries=3 \
    "https://archive.org/download/MoonlightSonata_755/Beethoven-MoonlightSonata.mp3" \
    -O /tmp/piano_raw.mp3 2>/dev/null || true

if [ -f /tmp/piano_raw.mp3 ] && [ -s /tmp/piano_raw.mp3 ]; then
    ffmpeg -y -i /tmp/piano_raw.mp3 -t 30 -ar 44100 -ac 2 /home/ga/Audio/samples/moonlight_sonata.wav 2>/dev/null || true
    rm -f /tmp/piano_raw.mp3
fi

# 2. LibriVox - Art of War narration (real human speech recording)
wget -q --timeout=60 --tries=3 \
    "https://archive.org/download/art_of_war_librivox/art_of_war_01_sun_tzu_64kb.mp3" \
    -O /tmp/speech_raw.mp3 2>/dev/null || true

if [ -f /tmp/speech_raw.mp3 ] && [ -s /tmp/speech_raw.mp3 ]; then
    ffmpeg -y -i /tmp/speech_raw.mp3 -t 30 -ar 44100 -ac 1 /home/ga/Audio/samples/narration.wav 2>/dev/null || true
    rm -f /tmp/speech_raw.mp3
fi

# 3. Wikimedia Commons fallback sources
SAMPLE_COUNT=$(ls /home/ga/Audio/samples/*.wav 2>/dev/null | wc -l)
if [ "$SAMPLE_COUNT" -lt 2 ]; then
    echo "Trying Wikimedia Commons sources..."
    wget -q --timeout=60 --tries=3 \
        "https://upload.wikimedia.org/wikipedia/commons/6/6d/Good_Morning.ogg" \
        -O /tmp/morning_raw.ogg 2>/dev/null || true
    if [ -f /tmp/morning_raw.ogg ] && [ -s /tmp/morning_raw.ogg ]; then
        ffmpeg -y -i /tmp/morning_raw.ogg -ar 44100 -ac 2 /home/ga/Audio/samples/good_morning.wav 2>/dev/null || true
        rm -f /tmp/morning_raw.ogg
    fi
fi

# Fix ownership
chown -R ga:ga /home/ga/Audio

# Clean up apt cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== Ardour installation complete ==="
echo "Audio samples in /home/ga/Audio/samples/:"
ls -la /home/ga/Audio/samples/ 2>/dev/null || echo "(none)"
