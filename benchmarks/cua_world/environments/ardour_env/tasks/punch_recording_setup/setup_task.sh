#!/bin/bash
echo "=== Setting up punch_recording_setup task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Define session paths
SESSION_DIR="/home/ga/Audio/sessions/MyProject"
SESSION_FILE="$SESSION_DIR/MyProject.ardour"

# Kill any existing Ardour instances
kill_ardour

# Verify session exists (ardour_env should have created this)
if [ ! -f "$SESSION_FILE" ]; then
    echo "ERROR: Session file not found at $SESSION_FILE"
    exit 1
fi

# Ensure there is an audio track with some content to give context
# Check if any audio route exists, if not we'll rely on the default ones
TRACK_COUNT=$(grep -c '<Route.*default-type="audio"' "$SESSION_FILE" 2>/dev/null || echo "0")
if [ "$TRACK_COUNT" -eq 0 ]; then
    echo "WARNING: No audio tracks found in session, agent will need to work with default layout or create one."
fi

# Strip any existing punch/loop configurations to ensure a clean state
echo "Cleaning existing punch/loop configurations..."
python3 -c "
import xml.etree.ElementTree as ET
try:
    tree = ET.parse('$SESSION_FILE')
    root = tree.getroot()
    changed = False
    
    # Remove AutoPunch and AutoLoop locations
    locations = root.find('Locations')
    if locations is not None:
        for loc in list(locations):
            flags = loc.get('flags', '')
            if 'IsAutoPunch' in flags or 'IsAutoLoop' in flags:
                locations.remove(loc)
                changed = True
                
    # Disable punch options
    for opt in root.iter('Option'):
        if opt.get('name') in ['punch-in', 'punch-out']:
            if opt.get('value') != '0':
                opt.set('value', '0')
                changed = True
                
    if changed:
        tree.write('$SESSION_FILE', encoding='UTF-8', xml_declaration=True)
        print('Cleaned session configuration.')
except Exception as e:
    print(f'Error cleaning session: {e}')
"

# Record initial session file modification time
stat -c %Y "$SESSION_FILE" > /tmp/initial_session_mtime.txt

# Launch Ardour with the session
echo "Launching Ardour with MyProject session..."
launch_ardour_session "$SESSION_FILE"

# Wait a moment for UI to settle
sleep 4

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="
echo "Task: Configure punch-in recording (punch range 8-14s, loop range 6-16s)"
echo "Session: $SESSION_FILE"