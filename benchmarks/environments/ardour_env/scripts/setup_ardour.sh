#!/bin/bash
# Do NOT use set -e: xdotool/wmctrl return non-zero for harmless reasons
# (e.g. "window not found") which would kill the script

echo "=== Setting up Ardour DAW ==="

# Wait for desktop to be ready
sleep 5

# Detect installed Ardour binary and version
ARDOUR_BIN=""
ARDOUR_VERSION=""
for v in 8 7 6; do
    if command -v "ardour${v}" &>/dev/null; then
        ARDOUR_BIN="ardour${v}"
        ARDOUR_VERSION="${v}"
        break
    fi
done
if [ -z "$ARDOUR_BIN" ]; then
    if command -v ardour &>/dev/null; then
        ARDOUR_BIN="ardour"
        ARDOUR_VERSION=$($ARDOUR_BIN --version 2>&1 | grep -oP 'Ardour(\d+)' | grep -oP '\d+' | head -1 || echo "6")
    else
        echo "ERROR: Ardour binary not found!"
        exit 1
    fi
fi
echo "Detected Ardour: $ARDOUR_BIN (version $ARDOUR_VERSION)"

# Store for other scripts
echo "$ARDOUR_BIN" > /tmp/ardour_bin_name
echo "$ARDOUR_VERSION" > /tmp/ardour_version

# Config directory
ARDOUR_CONFIG_DIR="/home/ga/.config/ardour${ARDOUR_VERSION}"
mkdir -p "$ARDOUR_CONFIG_DIR"
chown -R ga:ga "/home/ga/.config"

# Create working directories
su - ga -c "mkdir -p /home/ga/Audio/sessions /home/ga/Audio/export /home/ga/Desktop"

# Create Ardour session using CLI tool
echo "=== Creating Ardour session ==="
SESSION_DIR="/home/ga/Audio/sessions/MyProject"
if [ ! -f "$SESSION_DIR/MyProject.ardour" ]; then
    su - ga -c "ardour${ARDOUR_VERSION}-new_session -s 44100 '$SESSION_DIR' MyProject" 2>/dev/null || \
    su - ga -c "${ARDOUR_BIN}-new_session -s 44100 '$SESSION_DIR' MyProject" 2>/dev/null || true
    echo "Session created at $SESSION_DIR"
fi

# Copy an audio sample as import target for tasks
# Prefer narration.wav (different content from moonlight_sonata.wav embedded in the track)
IMPORT_SRC=""
for f in /home/ga/Audio/samples/narration.wav /home/ga/Audio/samples/good_morning.wav /home/ga/Audio/samples/*.wav; do
    if [ -f "$f" ]; then
        IMPORT_SRC="$f"
        break
    fi
done
if [ -n "$IMPORT_SRC" ] && [ -f "$IMPORT_SRC" ]; then
    cp "$IMPORT_SRC" /home/ga/Audio/import_me.wav
    chown ga:ga /home/ga/Audio/import_me.wav
    echo "Import target: $(basename "$IMPORT_SRC") -> import_me.wav"
fi

# =====================================================================
# WARM-UP LAUNCH: Complete first-run wizard, configure audio engine,
# index plugins, dismiss dialogs. After this, subsequent launches
# go straight to the session.
# =====================================================================
echo "=== Warm-up launch of Ardour (step 1: complete wizard) ==="

# Launch Ardour without session to trigger the wizard
su - ga -c "DISPLAY=:1 setsid ${ARDOUR_BIN} > /tmp/ardour_warmup.log 2>&1 &"

# Wait for any Ardour window
echo "Waiting for Ardour window..."
WID=""
for i in $(seq 1 40); do
    WID=$(DISPLAY=:1 xdotool search --name "Ardour" 2>/dev/null | head -1)
    [ -n "$WID" ] && break
    sleep 2
done

if [ -n "$WID" ]; then
    echo "Ardour window found: $WID"
    sleep 3

    # Click through the first-run wizard Forward button repeatedly
    # Forward button at (805, 492) in 1280x720 -> (1208, 738) in 1920x1080
    echo "Clicking through wizard..."
    for step in $(seq 1 10); do
        DISPLAY=:1 xdotool mousemove 1208 738 click 1 2>/dev/null || true
        sleep 2
    done

    # After wizard, a Session Setup dialog appears - click Quit
    # Quit button at (645, 554) in 1280x720 -> (968, 831)
    sleep 2
    DISPLAY=:1 xdotool mousemove 968 831 click 1 2>/dev/null || true
    sleep 3
else
    echo "WARNING: No Ardour window appeared during warm-up"
fi

# Kill warm-up instance
pkill -f "/usr/lib/ardour" 2>/dev/null || true
sleep 3
pkill -9 -f "/usr/lib/ardour" 2>/dev/null || true
sleep 2

# =====================================================================
# STEP 2: Configure audio engine via config file (no UI interaction)
# The Dummy backend works without any real audio hardware.
# We write the EngineStates directly into the config file.
# =====================================================================
echo "=== Configuring audio engine (Dummy backend) ==="

if [ -f "$ARDOUR_CONFIG_DIR/config" ]; then
    # Unhide the Dummy backend
    sed -i 's/name="hide-dummy-backend" value="1"/name="hide-dummy-backend" value="0"/' "$ARDOUR_CONFIG_DIR/config"

    # Inject EngineStates for Dummy backend using Python (reliable XML manipulation)
    python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import sys

config_path = sys.argv[1] if len(sys.argv) > 1 else "/home/ga/.config/ardour6/config"

try:
    tree = ET.parse(config_path)
    root = tree.getroot()

    # Remove any existing EngineStates (could be partial/broken)
    for es in root.findall('.//EngineStates'):
        parent = root
        for p in root.iter():
            if es in list(p):
                p.remove(es)
                break

    # Find or create Extra > AudioMIDISetup section
    extra = root.find('Extra')
    if extra is None:
        extra = ET.SubElement(root, 'Extra')
    audio_setup = extra.find('AudioMIDISetup')
    if audio_setup is None:
        audio_setup = ET.SubElement(extra, 'AudioMIDISetup')

    # Add EngineStates with Dummy backend
    engine_states = ET.SubElement(audio_setup, 'EngineStates')
    state = ET.SubElement(engine_states, 'State')
    state.set('backend', 'None (Dummy)')
    state.set('driver', 'Normal Speed')
    state.set('device', 'Silence')
    state.set('input-device', '')
    state.set('output-device', '')
    state.set('sample-rate', '44100')
    state.set('buffer-size', '1024')
    state.set('n-periods', '0')
    state.set('input-latency', '0')
    state.set('output-latency', '0')
    state.set('input-channels', '0')
    state.set('output-channels', '0')
    state.set('lm-input', '')
    state.set('lm-output', '')
    state.set('active', '1')
    state.set('use-buffered-io', '0')
    state.set('midi-option', '1 in, 1 out, Silence')
    state.set('lru', '1')
    midi_devices = ET.SubElement(state, 'MIDIDevices')

    # Write back
    ET.indent(tree, space='  ')
    tree.write(config_path, xml_declaration=True, encoding='UTF-8')
    print("EngineStates configured for Dummy backend")
except Exception as e:
    print(f"WARNING: Failed to configure EngineStates: {e}")
PYEOF

    chown ga:ga "$ARDOUR_CONFIG_DIR/config"
    echo "Config updated with Dummy backend engine state"
else
    echo "WARNING: Ardour config file not found at $ARDOUR_CONFIG_DIR/config"
fi

# =====================================================================
# STEP 3: Verification launch - start Ardour with session to confirm
# config works, index plugins, and close cleanly.
# =====================================================================
echo "=== Verification launch (indexing plugins, saving config) ==="

su - ga -c "DISPLAY=:1 setsid ${ARDOUR_BIN} '$SESSION_DIR/MyProject.ardour' > /tmp/ardour_warmup2.log 2>&1 &"

# Wait for session to load (should go straight through with Dummy backend)
echo "Waiting for session to load..."
SESSION_LOADED=0
for i in $(seq 1 90); do
    WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
    if echo "$WINDOWS" | grep -q "MyProject"; then
        echo "Session loaded after $((i*2))s"
        SESSION_LOADED=1
        break
    fi
    # If Audio/MIDI Setup dialog appears, the config didn't take effect
    # Handle it by clicking through
    SETUP_WID=$(DISPLAY=:1 xdotool search --name "Audio/MIDI Setup" 2>/dev/null | head -1)
    if [ -n "$SETUP_WID" ]; then
        echo "Audio/MIDI Setup appeared despite config - handling via UI..."
        # Get window geometry to compute relative click positions
        GEOM=$(DISPLAY=:1 xdotool getwindowgeometry "$SETUP_WID" 2>/dev/null || echo "")
        WX=$(echo "$GEOM" | grep -oP 'Position: \K\d+')
        WY=$(echo "$GEOM" | grep -oP ',\K\d+(?= )')
        WW=$(echo "$GEOM" | grep -oP 'Geometry: \K\d+')
        WH=$(echo "$GEOM" | grep -oP 'x\K\d+$')
        if [ -n "$WX" ] && [ -n "$WY" ]; then
            echo "Dialog at ($WX,$WY) size ${WW}x${WH}"
            # Audio System dropdown is ~35% from left, ~7% from top of dialog
            DX=$((WX + WW * 55 / 100))
            DY=$((WY + 35))
            DISPLAY=:1 xdotool mousemove "$DX" "$DY" click 1 2>/dev/null || true
            sleep 2
            # Select "None (Dummy)" - third item in dropdown (~7% + 3*item_height)
            DY2=$((DY + 55))
            DISPLAY=:1 xdotool mousemove "$DX" "$DY2" click 1 2>/dev/null || true
            sleep 2
            # Click Start button (~75% from left, same row as Audio System)
            SX=$((WX + WW * 78 / 100))
            SY=$((WY + 35))
            for attempt in $(seq 1 3); do
                DISPLAY=:1 xdotool mousemove "$SX" "$SY" click 1 2>/dev/null || true
                sleep 3
            done
        fi
    fi
    sleep 2
done

if [ "$SESSION_LOADED" -eq 1 ]; then
    # Add an audio track (tasks need at least one track)
    echo "Adding default audio track..."
    sleep 2
    # Focus main window and maximize
    DISPLAY=:1 wmctrl -r "MyProject" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    # Ctrl+Shift+N opens Add Track/Bus/VCA dialog
    DISPLAY=:1 xdotool key ctrl+shift+n 2>/dev/null || true
    sleep 3
    # Find the Add Track dialog and click "Add and Close" button
    ADD_WID=$(DISPLAY=:1 xdotool search --name "Add Track" 2>/dev/null | head -1)
    if [ -n "$ADD_WID" ]; then
        GEOM=$(DISPLAY=:1 xdotool getwindowgeometry "$ADD_WID" 2>/dev/null || echo "")
        AWX=$(echo "$GEOM" | grep -oP 'Position: \K\d+')
        AWY=$(echo "$GEOM" | grep -oP ',\K\d+(?= )')
        AWW=$(echo "$GEOM" | grep -oP 'Geometry: \K\d+')
        AWH=$(echo "$GEOM" | grep -oP 'x\K\d+$')
        if [ -n "$AWX" ] && [ -n "$AWY" ]; then
            # "Add and Close" button is at bottom-right of dialog
            # (~66px from right edge, ~67px from bottom edge)
            BTN_X=$((AWX + AWW - 66))
            BTN_Y=$((AWY + AWH - 67))
            echo "Clicking Add and Close at ($BTN_X,$BTN_Y)..."
            DISPLAY=:1 xdotool mousemove "$BTN_X" "$BTN_Y" click 1 2>/dev/null || true
        fi
    else
        echo "WARNING: Add Track dialog not found"
    fi
    sleep 3
    echo "Audio track added"

    # Save session first, then close
    echo "Saving session..."
    DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
    sleep 3
    echo "Closing Ardour cleanly..."
    DISPLAY=:1 xdotool key ctrl+q 2>/dev/null || true
    sleep 5
fi

pkill -f "/usr/lib/ardour" 2>/dev/null || true
sleep 3
pkill -9 -f "/usr/lib/ardour" 2>/dev/null || true
sleep 2

# =====================================================================
# STEP 4: Embed audio into Audio 1 track via session XML modification.
# This ensures the session has real audio content so export produces
# actual audio (not silence) and waveforms are visible in the editor.
# =====================================================================
echo "=== Embedding audio into Audio 1 track ==="

EMBED_AUDIO=""
for f in /home/ga/Audio/samples/moonlight_sonata.wav /home/ga/Audio/samples/good_morning.wav /home/ga/Audio/samples/*.wav; do
    if [ -f "$f" ]; then
        EMBED_AUDIO="$f"
        break
    fi
done

if [ -n "$EMBED_AUDIO" ] && [ -f "$SESSION_DIR/MyProject.ardour" ]; then
    python3 << 'EMBED_PYEOF'
import xml.etree.ElementTree as ET
import wave
import os
import shutil
import glob

session_path = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
interchange_dir = "/home/ga/Audio/sessions/MyProject/interchange/MyProject/audiofiles"

embed_audio = None
for candidate in ["/home/ga/Audio/samples/moonlight_sonata.wav",
                  "/home/ga/Audio/samples/good_morning.wav"] + \
                 glob.glob("/home/ga/Audio/samples/*.wav"):
    if os.path.exists(candidate):
        embed_audio = candidate
        break

if not embed_audio:
    print("No audio samples found, skipping embed")
    exit(0)

if not os.path.exists(session_path):
    print("Session file not found, skipping embed")
    exit(0)

basename = os.path.basename(embed_audio)
print(f"Embedding {basename} into session")

try:
    with wave.open(embed_audio, 'r') as wf:
        n_channels = wf.getnchannels()
        n_frames = wf.getnframes()
        sample_rate = wf.getframerate()
    print(f"  {n_channels}ch, {n_frames} frames, {sample_rate}Hz")
except Exception as e:
    print(f"Could not read audio file: {e}")
    exit(0)

os.makedirs(interchange_dir, exist_ok=True)
dest = os.path.join(interchange_dir, basename)
if not os.path.exists(dest):
    shutil.copy2(embed_audio, dest)
    print(f"  Copied to interchange/audiofiles/")

try:
    tree = ET.parse(session_path)
except ET.ParseError as e:
    print(f"Could not parse session XML: {e}")
    exit(0)

root = tree.getroot()

sources = root.find('Sources')
if sources is not None:
    existing = [s for s in sources.findall('Source') if s.get('name') == basename]
    if existing:
        print("Audio already embedded in session")
        exit(0)

id_counter = int(root.get('id-counter', '256'))

if sources is None:
    sources = ET.SubElement(root, 'Sources')

source_ids = []
for ch in range(n_channels):
    src_id = id_counter + 1
    id_counter += 1
    source_ids.append(str(src_id))
    src = ET.SubElement(sources, 'Source')
    src.set('name', basename)
    src.set('type', 'audio')
    src.set('flags', '')
    src.set('id', str(src_id))
    src.set('channel', str(ch))
    src.set('origin', '')
    src.set('natural-position', '0')
    print(f"  Added Source id={src_id} channel={ch}")

playlists = root.find('Playlists')
if playlists is None:
    print("No Playlists section found, skipping region")
    root.set('id-counter', str(id_counter + 10))
    ET.indent(tree, space='  ')
    tree.write(session_path, xml_declaration=True, encoding='UTF-8')
    exit(0)

audio1_pl = None
for pl in playlists.findall('Playlist'):
    pname = pl.get('name', '')
    if 'Audio 1' in pname:
        audio1_pl = pl
        break

if audio1_pl is None:
    print("Audio 1 playlist not found, skipping region")
    root.set('id-counter', str(id_counter + 10))
    ET.indent(tree, space='  ')
    tree.write(session_path, xml_declaration=True, encoding='UTF-8')
    exit(0)

region_id = id_counter + 1
id_counter += 1
region_name = basename.rsplit('.', 1)[0]

region = ET.SubElement(audio1_pl, 'Region')
region.set('name', region_name)
region.set('muted', '0')
region.set('opaque', '1')
region.set('locked', '0')
region.set('automatic', '0')
region.set('whole-file', '1')
region.set('import', '0')
region.set('external', '0')
region.set('type', 'audio')
region.set('first-edit', 'nothing')
region.set('layer', '0')
region.set('flags', 'Opaque,DefaultFadeIn,DefaultFadeOut,WholeFile')
for i, sid in enumerate(source_ids):
    region.set(f'source-{i}', sid)
    region.set(f'master-source-{i}', sid)
region.set('start', '0')
region.set('length', str(n_frames))
region.set('position', '0')
region.set('beat', '0')
region.set('stretch', '1')
region.set('shift', '1')
region.set('channels', str(n_channels))
region.set('id', str(region_id))

print(f"  Added Region '{region_name}' ({n_frames} frames) to Audio 1 playlist")

root.set('id-counter', str(id_counter + 20))
ET.indent(tree, space='  ')
tree.write(session_path, xml_declaration=True, encoding='UTF-8')
print("Session file updated with audio content")
EMBED_PYEOF

    chown -R ga:ga "$SESSION_DIR"
    echo "Audio embedding complete"
else
    echo "WARNING: No audio sample or session file found for embedding"
fi

echo "=== Warm-up complete ==="

# Create desktop launcher
cat > /home/ga/Desktop/launch_ardour.sh << LAUNCHEOF
#!/bin/bash
export DISPLAY=:1
${ARDOUR_BIN} "\$@" &
LAUNCHEOF
chmod +x /home/ga/Desktop/launch_ardour.sh
chown ga:ga /home/ga/Desktop/launch_ardour.sh

echo "=== Ardour setup complete ==="
