#!/bin/bash
echo "=== Setting up MIDI Virtual Instrument Sketch task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Create directories
su - ga -c "mkdir -p /home/ga/Audio/midi"
su - ga -c "mkdir -p /home/ga/Audio/midi_render"
rm -f /home/ga/Audio/midi_render/*.wav 2>/dev/null || true

# Generate MIDI file using Python (no external libraries needed)
python3 << 'PYEOF'
import struct
import os

def write_midi_file(filename):
    """Write a valid SMF Type 0 MIDI file with a chromatic tension motif."""
    
    def var_len(value):
        result = []
        result.append(value & 0x7F)
        value >>= 7
        while value:
            result.append((value & 0x7F) | 0x80)
            value >>= 7
        result.reverse()
        return bytes(result)
    
    track_data = bytearray()
    
    # Tempo: 120 BPM = 500000 microseconds per quarter note
    track_data += var_len(0)
    track_data += bytes([0xFF, 0x51, 0x03])
    track_data += struct.pack('>I', 500000)[1:]
    
    # Time signature: 4/4
    track_data += var_len(0)
    track_data += bytes([0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08])
    
    # Track name
    name = b'Tension Motif'
    track_data += var_len(0)
    track_data += bytes([0xFF, 0x03, len(name)]) + name
    
    # Notes: chromatic tension-building pattern
    ppq = 480
    notes = [
        (60, 90, ppq),        (61, 85, ppq // 2),   (64, 95, ppq // 2),
        (63, 88, ppq),        (65, 92, ppq),        (66, 80, ppq // 2),
        (64, 88, ppq // 2),   (67, 95, ppq),        (69, 100, ppq),
        (68, 85, ppq // 2),   (70, 90, ppq // 2),   (71, 95, ppq),
        (67, 82, ppq),        (72, 100, ppq * 2),   (71, 88, ppq),
        (72, 100, ppq * 2),
    ]
    
    for pitch, vel, dur in notes:
        track_data += var_len(0)
        track_data += bytes([0x90, pitch, vel])
        track_data += var_len(dur)
        track_data += bytes([0x80, pitch, 0])
    
    track_data += var_len(0)
    track_data += bytes([0xFF, 0x2F, 0x00])
    
    with open(filename, 'wb') as f:
        f.write(b'MThd')
        f.write(struct.pack('>I', 6))
        f.write(struct.pack('>H', 0))
        f.write(struct.pack('>H', 1))
        f.write(struct.pack('>H', 480))
        f.write(b'MTrk')
        f.write(struct.pack('>I', len(track_data)))
        f.write(track_data)

write_midi_file('/home/ga/Audio/midi/tension_motif.mid')
PYEOF

chown ga:ga /home/ga/Audio/midi/tension_motif.mid

# Verify MIDI file was created
if [ ! -f /home/ga/Audio/midi/tension_motif.mid ]; then
    echo "ERROR: Failed to create MIDI file!"
    exit 1
fi

# Create a brief/instruction file for the agent
cat > /home/ga/Audio/midi/README.txt << 'EOF'
MIDI Virtual Instrument Sketch - Production Brief
===================================================
Project: Thriller Film Score - Tension Motif Sketch
Composer Workstation: Ardour DAW

Files:
  tension_motif.mid  -  Chromatic tension-building melody (120 BPM)

Instructions:
1. Create a new MIDI track in Ardour named "Tension Motif"
2. Add the ACE Reasonable Synth (or any available built-in synth) as the instrument
3. Import tension_motif.mid onto the MIDI track
4. Export/render the audio to: /home/ga/Audio/midi_render/tension_motif.wav

The director needs the rendered WAV by end of day for temp scoring review.
EOF
chown ga:ga /home/ga/Audio/midi/README.txt

# Ensure Ardour is running with the session
kill_ardour 2>/dev/null || true
SESSION_PATH="/home/ga/Audio/sessions/MyProject/MyProject.ardour"

# Create clean backup if missing
if [ ! -f "${SESSION_PATH}.clean_backup" ] && [ -f "$SESSION_PATH" ]; then
    cp "$SESSION_PATH" "${SESSION_PATH}.clean_backup"
fi
# Restore clean session
if [ -f "${SESSION_PATH}.clean_backup" ]; then
    cp "${SESSION_PATH}.clean_backup" "$SESSION_PATH"
fi

if type launch_ardour_session &>/dev/null; then
    launch_ardour_session "$SESSION_PATH"
else
    # Fallback launch
    su - ga -c "DISPLAY=:1 ardour8 '$SESSION_PATH' &" || \
    su - ga -c "DISPLAY=:1 ardour '$SESSION_PATH' &"
    sleep 15
fi

# Focus and maximize
DISPLAY=:1 wmctrl -r "MyProject" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "MyProject" 2>/dev/null || true

# Dismiss any dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== MIDI Instrument Sketch task setup complete ==="