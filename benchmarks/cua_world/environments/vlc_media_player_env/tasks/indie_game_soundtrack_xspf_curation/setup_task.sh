#!/bin/bash
set -e
echo "=== Setting up Indie Game Soundtrack XSPF Curation Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create directories
mkdir -p /home/ga/Music/composer_delivery
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Desktop

# Clean previous state if it exists
rm -rf /home/ga/Desktop/OST_Distribution 2>/dev/null || true
rm -f /home/ga/Documents/draft_ost.m3u 2>/dev/null || true
rm -rf /home/ga/Music/composer_delivery/* 2>/dev/null || true

echo "Downloading real audio sample for realistic data generation..."
wget -qO /tmp/real_audio.ogg "https://upload.wikimedia.org/wikipedia/commons/3/30/J._S._Bach_-_Fugue_in_G_minor%2C_BWV_1000.ogg" || true

if [ ! -f /tmp/real_audio.ogg ]; then
    echo "Fallback to local sample audio..."
    # Create a quick 60s noise file as fallback to avoid synthetic test patterns if possible
    ffmpeg -y -f lavfi -i "anoisesrc=c=pink:r=44100:a=0.5" -t 60 -q:a 5 /tmp/real_audio.ogg 2>/dev/null
fi

# Python script to orchestrate the generation of 25 tracks with specific metadata
cat << 'EOF' > /tmp/generate_tracks.py
import os
import subprocess
import json

tracks = [
    # The 12 selected tracks
    ("01_main_theme_vFINAL.mp3", "Cyber-Neon Main Theme", True),
    ("intro_sketch.mp3", "Intro Sketch (Reject)", False),
    ("02_city_streets_mix2.mp3", "Neon Skyline", True),
    ("03_combat_loop.mp3", "Alleyway Ambush", True),
    ("combat_alt_take.mp3", "Alleyway Ambush (Alt Take)", False),
    ("04_hacking_minigame.mp3", "Data Breach", True),
    ("stealth_concept.mp3", "Shadow Ops (Concept)", False),
    ("05_stealth_v1.mp3", "Shadow Ops", True),
    ("06_boss_fight_MASTER.mp3", "Corporate Overlord", True),
    ("boss_fight_no_drums.mp3", "Corporate Overlord (Stem)", False),
    ("07_shop_theme.mp3", "Black Market", True),
    ("08_safehouse.mp3", "Neon Dreams", True),
    ("safehouse_ambient.mp3", "Neon Dreams (Ambient)", False),
    ("09_chase_sequence.mp3", "Highway Pursuit", True),
    ("chase_sequence_v2.mp3", "Highway Pursuit (V2)", False),
    ("10_ending_credits.mp3", "Cyber-Neon Finale", True),
    ("11_bonus_track_1.mp3", "Retro Grade", True),
    ("12_bonus_track_2.mp3", "Synthwave Nights", True)
]

# Add remaining dummy rejects to reach exactly 25 tracks
extra_rejects = [
    ("menu_loop_old.mp3", "Main Menu (Alpha)"),
    ("trailer_music.mp3", "E3 Trailer Audio"),
    ("sfx_pack_1.mp3", "UI Sounds Mix"),
    ("dialogue_test.mp3", "Voiceover Test"),
    ("credits_instrumental.mp3", "Cyber-Neon Finale (Inst)"),
    ("boss_phase2.mp3", "Corporate Overlord P2"),
    ("ambient_room_tone.mp3", "Room Tone")
]

for filename, title in extra_rejects:
    tracks.append((filename, title, False))

m3u_lines = []
time_offset = 0

for idx, (filename, title, is_selected) in enumerate(tracks):
    filepath = f"/home/ga/Music/composer_delivery/{filename}"
    
    # Extract 2 seconds of real audio to make the file
    subprocess.run([
        "ffmpeg", "-y", "-i", "/tmp/real_audio.ogg", "-ss", str(time_offset), "-t", "2",
        "-c:a", "libmp3lame", "-q:a", "5", 
        "-metadata", f"title={title}", 
        "-metadata", "artist=Neon Syndicate Games",
        filepath
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    time_offset += 2
    
    if is_selected:
        m3u_lines.append(filepath)

# Write the draft M3U playlist
with open("/home/ga/Documents/draft_ost.m3u", "w") as f:
    f.write("#EXTM3U\n")
    for line in m3u_lines:
        f.write(f"{line}\n")

EOF

echo "Generating tracks..."
python3 /tmp/generate_tracks.py

# Fix permissions
chown -R ga:ga /home/ga/Music /home/ga/Documents /home/ga/Desktop

# Ensure VLC is not running
pkill -f "vlc" > /dev/null 2>&1 || true

# Open a file manager window to prompt the user visually
su - ga -c "DISPLAY=:1 nautilus /home/ga/Music/composer_delivery &" 2>/dev/null || true

# Take screenshot of initial state
sleep 3
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="