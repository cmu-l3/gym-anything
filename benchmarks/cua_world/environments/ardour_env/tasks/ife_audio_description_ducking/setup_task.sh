#!/bin/bash
echo "=== Setting up IFE Audio Description task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Kill any existing Ardour instances
kill_ardour

SESSION_DIR="/home/ga/Audio/sessions/MyProject"
SESSION_FILE="$SESSION_DIR/MyProject.ardour"

# Create required output directory
su - ga -c "mkdir -p /home/ga/Audio/ife_mix"
rm -f /home/ga/Audio/ife_mix/*.wav 2>/dev/null || true

# Ensure narration and music samples exist
SAMPLES_DIR="/home/ga/Audio/samples"
if [ ! -f "$SAMPLES_DIR/narration.wav" ]; then
    # Fallback if standard narration is missing
    cp "$SAMPLES_DIR/art_of_war.wav" "$SAMPLES_DIR/narration.wav" 2>/dev/null || \
    cp "$SAMPLES_DIR/good_morning.wav" "$SAMPLES_DIR/narration.wav" 2>/dev/null
fi
chown ga:ga "$SAMPLES_DIR/narration.wav" 2>/dev/null || true

# Python script to cleanly prepare the starting XML state
# Ensures Track 1 is named "Program" and has the moonlight sonata audio.
cat > /tmp/prepare_session.py << 'PYEOF'
import xml.etree.ElementTree as ET
import sys
import os

session_file = sys.argv[1]
if not os.path.exists(session_file):
    sys.exit(0)

try:
    tree = ET.parse(session_file)
    root = tree.getroot()
    
    # Remove existing markers to ensure clean slate
    locations = root.find('Locations')
    if locations is not None:
        for loc in locations.findall('Location'):
            flags = loc.get('flags', '')
            if 'IsMark' in flags and 'IsSessionRange' not in flags:
                locations.remove(loc)

    # Find the first audio route (not master/monitor) and rename to "Program"
    # Also attempt to replace its source with moonlight_sonata.wav
    audio_route = None
    for route in root.findall('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' not in flags and 'MonitorOut' not in flags and route.get('default-type') == 'audio':
            audio_route = route
            break
            
    if audio_route is not None:
        audio_route.set('name', 'Program')
        
        # Replace source path in the global Sources list to point to the music
        sources = root.find('Sources')
        if sources is not None:
            for source in sources.findall('Source'):
                if source.get('origin', '').endswith('.wav'):
                    source.set('origin', '/home/ga/Audio/samples/moonlight_sonata.wav')
                    source.set('name', 'moonlight_sonata.wav')

    tree.write(session_file, xml_declaration=True, encoding='UTF-8')
    print("Session XML prepared successfully.")
except Exception as e:
    print(f"Error preparing XML: {e}")
PYEOF

# Run preparation script
python3 /tmp/prepare_session.py "$SESSION_FILE"

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_FILE"

sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="