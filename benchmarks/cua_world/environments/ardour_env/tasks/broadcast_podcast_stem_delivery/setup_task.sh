#!/bin/bash
echo "=== Setting up broadcast_podcast_stem_delivery task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback functions in case task_utils is missing
if ! command -v kill_ardour &>/dev/null; then
    kill_ardour() {
        pkill -f "/usr/lib/ardour" 2>/dev/null || true
        sleep 2
        pkill -9 -f "/usr/lib/ardour" 2>/dev/null || true
        sleep 1
    }
fi

SESSION_DIR="/home/ga/Audio/sessions/MyProject"
SESSION_FILE="$SESSION_DIR/MyProject.ardour"
BACKUP_FILE="$SESSION_DIR/MyProject.ardour.clean_backup"
AUDIO_DIR="$SESSION_DIR/interchange/MyProject/audiofiles"
DELIVERY_DIR="/home/ga/Audio/podcast_delivery"

# Kill any existing Ardour instances
kill_ardour

# Ensure session exists
if [ ! -f "$SESSION_FILE" ]; then
    echo "Session file missing. Running default setup..."
    /workspace/scripts/setup_ardour.sh
fi

# Create backup of clean session on first run
if [ ! -f "$BACKUP_FILE" ] && [ -f "$SESSION_FILE" ]; then
    cp "$SESSION_FILE" "$BACKUP_FILE"
fi

# Restore clean session
if [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$SESSION_FILE"
fi

# =====================================================================
# Clean stale outputs BEFORE recording timestamp
# =====================================================================
rm -rf "$DELIVERY_DIR" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_timestamp
stat -c %Y "$SESSION_FILE" > /tmp/initial_session_mtime

# =====================================================================
# Generate 4 audio files via ffmpeg (ZERO network dependency)
# =====================================================================
echo "Generating audio files..."
mkdir -p "$AUDIO_DIR"

ffmpeg -y -f lavfi -i "anoisesrc=d=30:c=pink:r=44100:a=0.3" \
    -af "bandpass=f=800:width_type=h:w=2400" \
    -ac 2 "$AUDIO_DIR/host_narration.wav" 2>/dev/null

ffmpeg -y -f lavfi -i "anoisesrc=d=30:c=pink:r=44100:a=0.25" \
    -af "bandpass=f=600:width_type=h:w=2000" \
    -ac 2 "$AUDIO_DIR/guest_interview.wav" 2>/dev/null

ffmpeg -y -f lavfi -i "sine=f=440:d=30" \
    -f lavfi -i "sine=f=554:d=30" \
    -f lavfi -i "sine=f=659:d=30" \
    -filter_complex "[0][1][2]amix=inputs=3:duration=longest" \
    -ar 44100 -ac 2 "$AUDIO_DIR/music_bed.wav" 2>/dev/null

ffmpeg -y -f lavfi -i "anoisesrc=d=30:c=white:r=44100:a=0.4" \
    -af "tremolo=f=3:d=0.7" \
    -ac 2 "$AUDIO_DIR/sfx_hits.wav" 2>/dev/null

echo "Audio files generated"

# =====================================================================
# Create 4 named tracks + register audio sources via XML
# Uses the proven session_bus_routing pattern (no audio-playlist attr).
# Tracks start empty; agent imports audio from audiofiles directory.
# =====================================================================
echo "Configuring session with 4 tracks..."

python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import copy, os, wave, sys

session_file = '/home/ga/Audio/sessions/MyProject/MyProject.ardour'
audio_dir = '/home/ga/Audio/sessions/MyProject/interchange/MyProject/audiofiles'

if not os.path.exists(session_file):
    print("ERROR: Session file not found"); sys.exit(1)

tree = ET.parse(session_file)
root = tree.getroot()
sample_rate = int(root.get('sample-rate', '44100'))

track_names = ["Host", "Guest", "Music_Bed", "SFX"]
wav_files = ["host_narration.wav", "guest_interview.wav", "music_bed.wav", "sfx_hits.wav"]

# ---- Create 4 named tracks (session_bus_routing pattern) ----
audio_routes = [r for r in root.iter('Route')
                if r.get('default-type') == 'audio'
                and 'MasterOut' not in r.get('flags', '')
                and 'MonitorOut' not in r.get('flags', '')]

if not audio_routes:
    print("ERROR: No template audio route found"); sys.exit(1)

base_route = audio_routes[0]
parent = {c: p for p in root.iter() for c in p}.get(base_route, root)

# Remove all existing audio tracks
for r in audio_routes:
    parent.remove(r)

# Keep existing playlists (Ardour 6 crashes if Playlists section is empty)

base_id = 20000
for i, name in enumerate(track_names):
    new_route = copy.deepcopy(base_route)
    new_route.set('name', name)
    new_route.set('id', str(base_id + i * 100))
    # Remove audio-playlist to avoid Ardour 6 crash on dangling reference
    if 'audio-playlist' in new_route.attrib:
        del new_route.attrib['audio-playlist']
    for io in new_route.findall('IO'):
        io.set('name', name)
        io.set('id', str(base_id + i * 100 + 1))
        for port in io.findall('Port'):
            old_pname = port.get('name', '')
            if '/' in old_pname:
                port.set('name', name + '/' + old_pname.split('/')[1])
    parent.append(new_route)
    print(f"  Created track '{name}'")

# ---- Register audio sources (so they appear in Ardour's source list) ----
sources = root.find('Sources')
if sources is None:
    sources = ET.SubElement(root, 'Sources')

src_id = 30000
for wav_file in wav_files:
    wav_path = os.path.join(audio_dir, wav_file)
    n_channels = 2
    try:
        with wave.open(wav_path, 'rb') as wf:
            n_channels = wf.getnchannels()
    except:
        pass
    for ch in range(n_channels):
        src = ET.SubElement(sources, 'Source')
        src.set('name', wav_file)
        src.set('type', 'audio')
        src.set('flags', '')
        src.set('id', str(src_id))
        src.set('channel', str(ch))
        src.set('origin', '')
        src.set('natural-position', '0')
        src_id += 1

# ---- Update session range to 30s ----
locations = root.find('Locations')
if locations is not None:
    for loc in locations.findall('Location'):
        if 'IsSessionRange' in loc.get('flags', ''):
            loc.set('end', str(30 * sample_rate))

root.set('id-counter', str(src_id + 1000))
tree.write(session_file, xml_declaration=True, encoding='UTF-8')
print("Session XML updated with 4 tracks")
PYEOF

chown -R ga:ga "$SESSION_DIR"

# =====================================================================
# Create delivery directory and mixing notes
# =====================================================================
mkdir -p "$DELIVERY_DIR"
chown ga:ga "$DELIVERY_DIR"

cat > /home/ga/Desktop/mixing_notes.txt << 'MIXNOTES'
=== PODCAST MIXING NOTES ===
Show: The Deep Dive - Episode 12
Engineer: [Your Name]
Date: 2025-03-18
Session: MyProject (Ardour)

--- AUDIO FILES ---
Import these files from the session audiofiles directory onto the matching tracks:
  * Host         <- host_narration.wav
  * Guest        <- guest_interview.wav
  * Music_Bed    <- music_bed.wav
  * SFX          <- sfx_hits.wav

--- BUS ROUTING ---
Create two stereo submix buses:
  * "Dialogue_Stem" -- receives: Host, Guest
  * "Music_Stem"    -- receives: Music_Bed, SFX
Remove all source tracks' direct outputs to Master.
Both buses must feed Master.

--- GAIN & PAN ---
  Track/Bus         Gain (dB)   Pan
  Host              0           Center
  Guest            -3           25% Right
  Music_Bed       -14           Center
  SFX              -8           100% Left (hard left)
  Dialogue_Stem    -1           Center (default)
  Music_Stem       -6           Center (default)

--- MUSIC DUCKING AUTOMATION ---
Draw gain automation on Music_Bed to duck under dialogue:
  Time (sec)  Gain (dB)
  0            0
  2           -18
  12          -18
  14            0
  16          -18
  26            0

--- CHAPTER MARKERS ---
  Marker Name        Position
  Cold_Open          0:00
  Interview_Start    0:05
  Deep_Dive          0:14
  Outro              0:26

--- STEM DELIVERY ---
Export to /home/ga/Audio/podcast_delivery/:
  * dialogue_stem.wav  (Dialogue_Stem bus only)
  * music_stem.wav     (Music_Stem bus only)
  * full_mix.wav       (Master / full session mix)
Format: 16-bit, 44.1 kHz, stereo WAV

--- ARCHIVE ---
Save a session snapshot named "EP12_Final_Mix"
MIXNOTES

chown ga:ga /home/ga/Desktop/mixing_notes.txt

# =====================================================================
# Record baseline state
# =====================================================================
INITIAL_TRACK_COUNT=$(grep -c '<Route.*default-type="audio"' "$SESSION_FILE" 2>/dev/null || echo "0")
echo "$INITIAL_TRACK_COUNT" > /tmp/initial_track_count
stat -c %Y "$SESSION_FILE" > /tmp/initial_session_mtime

# =====================================================================
# Launch Ardour
# =====================================================================
echo "Launching Ardour..."

if command -v launch_ardour_session &>/dev/null; then
    launch_ardour_session "$SESSION_FILE"
else
    su - ga -c "DISPLAY=:1 setsid ardour8 '$SESSION_FILE' > /tmp/ardour_task.log 2>&1 &" 2>/dev/null || \
    su - ga -c "DISPLAY=:1 setsid ardour '$SESSION_FILE' > /tmp/ardour_task.log 2>&1 &" 2>/dev/null || true
    sleep 8
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "MyProject"; then break; fi
        sleep 2
    done
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
fi

sleep 4

WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
fi

sleep 2

DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== broadcast_podcast_stem_delivery task setup complete ==="
