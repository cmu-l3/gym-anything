#!/bin/bash
echo "=== Setting up game_audio_asset_pipeline task ==="

source /workspace/scripts/task_utils.sh

# Kill any existing Ardour instances
kill_ardour

SESSION_DIR="/home/ga/Audio/sessions/MyProject"
SESSION_FILE="$SESSION_DIR/MyProject.ardour"
BACKUP_FILE="$SESSION_DIR/MyProject.ardour.clean_backup"

# Create backup of clean session on first run
if [ ! -f "$BACKUP_FILE" ] && [ -f "$SESSION_FILE" ]; then
    cp "$SESSION_FILE" "$BACKUP_FILE"
    echo "Created clean session backup"
fi

# Restore clean session
if [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$SESSION_FILE"
    echo "Restored clean session from backup"
fi

# Create export directory
su - ga -c "mkdir -p /home/ga/Audio/game_assets"
rm -f /home/ga/Audio/game_assets/*.wav 2>/dev/null || true
rm -f /home/ga/Audio/game_assets/*.txt 2>/dev/null || true

# Check that samples exist (from env setup)
if [ ! -f "/home/ga/Audio/samples/moonlight_sonata.wav" ] || [ ! -f "/home/ga/Audio/samples/narration.wav" ]; then
    echo "WARNING: Expected audio samples not found in /home/ga/Audio/samples/!"
    # The agent will have to fail or find alternates, but env should guarantee them.
fi

# Create the production brief
cat > /home/ga/Audio/game_audio_brief.txt << 'BRIEF'
================================================================
GAME AUDIO ASSET PIPELINE - PRODUCTION BRIEF
Project: "Echoes of Eternity" (Indie RPG)
================================================================

We are preparing raw recordings for the game engine. Please 
organize the session, define the assets with range markers,
level the tracks, and export everything following our pipeline.

1. TRACKS & ASSET DEFINITIONS
   Create two tracks and import the source files from 
   /home/ga/Audio/samples/:

   Track 1: "Music"
   - Import: moonlight_sonata.wav
   - Define 3 assets using named range markers:
       menu_music         -> 0s to 10s
       exploration_theme  -> 10s to 20s
       credits_music      -> 20s to 30s
   - Set Track Gain: -6 dB (music should sit below dialogue)

   Track 2: "Dialogue"
   - Import: narration.wav
   - Define 3 assets using named range markers:
       npc_intro          -> 0s to 8s
       quest_briefing     -> 8s to 16s
       npc_farewell       -> 16s to 24s
   - Set Track Gain: 0 dB (unity gain)

2. EXPORT ASSETS
   Export each of the 6 defined ranges as individual WAV files.
   Destination: /home/ga/Audio/game_assets/
   Filenames: Match the range marker names (e.g., menu_music.wav)

3. ASSET MANIFEST
   Create a plain text file at:
   /home/ga/Audio/game_assets/asset_manifest.txt
   List each asset on its own line with its category, filename, 
   and duration. Example:
   Music | menu_music.wav | 10s
   Dialogue | npc_intro.wav | 8s
================================================================
BRIEF

chown ga:ga /home/ga/Audio/game_audio_brief.txt

# Record baseline state
if [ -f "$SESSION_FILE" ]; then
    INITIAL_TRACK_COUNT=$(grep -c '<Route.*default-type="audio"' "$SESSION_FILE" 2>/dev/null || echo "0")
    echo "$INITIAL_TRACK_COUNT" > /tmp/initial_track_count
fi

# Record task start timestamp for anti-gaming (file mtime checks)
date +%s > /tmp/task_start_timestamp

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_FILE"

sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Instructions written to /home/ga/Audio/game_audio_brief.txt"