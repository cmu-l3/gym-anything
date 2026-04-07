#!/bin/bash
echo "=== Setting up bioacoustics_extraction task ==="

source /workspace/scripts/task_utils.sh

# Kill any existing Ardour instances
kill_ardour

SESSION_DIR="/home/ga/Audio/sessions/MyProject"
SESSION_FILE="$SESSION_DIR/MyProject.ardour"

# Create required directories
su - ga -c "mkdir -p /home/ga/Audio/bioacoustics_export"
rm -f /home/ga/Audio/bioacoustics_export/*.wav 2>/dev/null || true

# Rename the default track in the Ardour XML to "Raw Canopy"
if [ -f "$SESSION_FILE" ]; then
    python3 -c "
import xml.etree.ElementTree as ET
import sys
session_file = '$SESSION_FILE'
try:
    tree = ET.parse(session_file)
    root = tree.getroot()
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' not in flags and 'MonitorOut' not in flags:
            if route.get('default-type') == 'audio':
                route.set('name', 'Raw Canopy')
                break
    tree.write(session_file, encoding='UTF-8', xml_declaration=True)
    print('Renamed default track to Raw Canopy')
except Exception as e:
    print(f'Failed to modify session XML: {e}', file=sys.stderr)
"
fi

# Create the field notes document
cat > /home/ga/Audio/field_notes.txt << 'NOTES'
=======================================================
BIOACOUSTICS FIELD EXTRACTION NOTES
=======================================================
Location: Site 4, Pacific Northwest Canopy
Target Species: Northern Spotted Owl (Call type: 3-note)

Instructions:
1. Create a new audio track named "Target Species".
2. Extract the 3 target calls from the "Raw Canopy" track 
   and place them on the "Target Species" track.
3. Target timestamps (±0.5s tolerance):
   - Call 1: 00:05.0 to 00:08.0
   - Call 2: 00:14.0 to 00:16.0
   - Call 3: 00:22.0 to 00:25.0
4. Mute the "Raw Canopy" track so only the isolated calls play.
5. Boost the volume (gain) of the "Target Species" track by +6 dB
   (anything between +4 dB and +10 dB is acceptable).
6. Export the final mix as a WAV file to:
   /home/ga/Audio/bioacoustics_export/isolated_calls.wav
=======================================================
NOTES

chown ga:ga /home/ga/Audio/field_notes.txt

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_FILE"

sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="