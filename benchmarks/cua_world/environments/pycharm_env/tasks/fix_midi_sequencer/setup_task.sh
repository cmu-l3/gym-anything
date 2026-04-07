#!/bin/bash
set -e
echo "=== Setting up fix_midi_sequencer task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/PycharmProjects/midi_builder"

# 1. Clean previous state
rm -rf "$PROJECT_DIR"
rm -f /tmp/fix_midi_sequencer_result.json
rm -f /tmp/task_start_time

# 2. Create Project Structure
mkdir -p "$PROJECT_DIR/midi_builder"
mkdir -p "$PROJECT_DIR/tests"
mkdir -p "$PROJECT_DIR/output"

# 3. Create Files

# --- requirements.txt ---
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
pytest>=7.0
EOF

# --- midi_builder/__init__.py ---
touch "$PROJECT_DIR/midi_builder/__init__.py"

# --- midi_builder/constants.py ---
cat > "$PROJECT_DIR/midi_builder/constants.py" << 'EOF'
"""MIDI Protocol Constants."""
NOTE_ON = 0x90
NOTE_OFF = 0x80
META_EVENT = 0xFF
SET_TEMPO = 0x51
END_OF_TRACK = 0x2F
HEADER_CHUNK = b'MThd'
TRACK_CHUNK = b'MTrk'
EOF

# --- midi_builder/encoder.py (BUGGY) ---
# Bug 1: write_varlen uses >> 8 instead of >> 7
cat > "$PROJECT_DIR/midi_builder/encoder.py" << 'EOF'
"""Binary encoding utilities for MIDI."""

def write_varlen(value: int) -> bytes:
    """
    Encode an integer as a Variable Length Quantity (VLQ).
    MIDI uses 7 bits per byte, with the MSB as a continuation flag.
    """
    if value == 0:
        return b'\x00'

    bytes_list = []
    while value > 0:
        byte = value & 0x7F
        # BUG: Should be value >>= 7 for 7-bit chunks
        # This causes incorrect encoding for values > 127
        value >>= 8  
        
        if len(bytes_list) > 0:
            byte |= 0x80  # Set continuation bit
        bytes_list.insert(0, byte)
        
    return bytes(bytes_list)

def write_int_be(value: int, length: int) -> bytes:
    """Write integer as big-endian bytes."""
    return value.to_bytes(length, byteorder='big')
EOF

# --- midi_builder/sequencer.py (BUGGY) ---
# Bug 2: Delta time uses absolute time instead of relative
# Bug 3: Missing End of Track event
cat > "$PROJECT_DIR/midi_builder/sequencer.py" << 'EOF'
"""MIDI Sequencer logic."""
import struct
from .constants import *
from .encoder import write_varlen, write_int_be

class Note:
    def __init__(self, pitch, start_tick, duration, velocity=64):
        self.pitch = pitch
        self.start_tick = start_tick
        self.duration = duration
        self.velocity = velocity

class MidiTrack:
    def __init__(self):
        self.notes = []
        self.events = []

    def add_note(self, pitch, start, duration, velocity=64):
        self.notes.append(Note(pitch, start, duration, velocity))

    def _compile_events(self):
        """Convert notes to linear MIDI events (Note On/Off)."""
        events = []
        for note in self.notes:
            # Note On
            events.append({
                'tick': note.start_tick,
                'type': NOTE_ON,
                'data': [note.pitch, note.velocity]
            })
            # Note Off
            events.append({
                'tick': note.start_tick + note.duration,
                'type': NOTE_OFF,
                'data': [note.pitch, 0]
            })
        # Sort by time
        events.sort(key=lambda x: x['tick'])
        return events

    def to_bytes(self) -> bytes:
        events = self._compile_events()
        buffer = bytearray()
        
        last_tick = 0
        
        for event in events:
            # BUG: Delta time calculation logic is flawed.
            # MIDI delta time is (current_tick - previous_tick).
            # Here we are just using the event.tick (absolute time) 
            # effectively resetting the anchor every time or accumulating wrong.
            
            # Incorrect logic:
            delta = event['tick'] 
            # Correct logic should be: delta = event['tick'] - last_tick
            
            buffer.extend(write_varlen(delta))
            
            # Write status byte and data
            buffer.append(event['type'])
            buffer.extend(event['data'])
            
            last_tick = event['tick']

        # BUG: Missing End of Track Event
        # MIDI specs require FF 2F 00 at the end of every track chunk.
        # Missing lines:
        # buffer.extend(write_varlen(0))
        # buffer.append(META_EVENT)
        # buffer.append(END_OF_TRACK)
        # buffer.append(0)

        return bytes(buffer)

class MidiFile:
    def __init__(self):
        self.track = MidiTrack()

    def add_note(self, pitch, start, duration):
        self.track.add_note(pitch, start, duration)

    def save(self, filename):
        track_data = self.track.to_bytes()
        
        with open(filename, 'wb') as f:
            # Header Chunk: MThd, len=6, format=0, ntracks=1, division=480
            f.write(HEADER_CHUNK)
            f.write(write_int_be(6, 4))
            f.write(write_int_be(0, 2)) # Format 0
            f.write(write_int_be(1, 2)) # 1 Track
            f.write(write_int_be(480, 2)) # Ticks per quarter note
            
            # Track Chunk: MTrk, len, data
            f.write(TRACK_CHUNK)
            f.write(write_int_be(len(track_data), 4))
            f.write(track_data)
EOF

# --- tests/test_encoder.py ---
cat > "$PROJECT_DIR/tests/test_encoder.py" << 'EOF'
import pytest
from midi_builder.encoder import write_varlen

def test_vlq_single_byte():
    # 0 -> 00
    assert write_varlen(0) == b'\x00'
    # 127 -> 7F
    assert write_varlen(127) == b'\x7F'

def test_vlq_two_bytes():
    # 128 -> 81 00 (binary 10000001 00000000)
    # 128 is 1000 0000. 7-bit chunks: 1, 0000000.
    # First byte: 1 | 0x80 = 0x81. Second byte: 0x00.
    assert write_varlen(128) == b'\x81\x00'

def test_vlq_large_number():
    # 16383 (0x3FFF) -> FF 7F
    # 16383 is 11 1111 1111 1111 (14 ones)
    # Chunks: 1111111, 1111111
    # Byte 1: 0x7F | 0x80 = 0xFF
    # Byte 2: 0x7F
    assert write_varlen(16383) == b'\xFF\x7F'
EOF

# --- tests/test_sequencer.py ---
cat > "$PROJECT_DIR/tests/test_sequencer.py" << 'EOF'
import os
import struct
from midi_builder.sequencer import MidiFile

def test_delta_time_logic():
    # Create two notes at different times
    # Note 1: Start 0
    # Note 2: Start 480 (delta should be 480)
    midi = MidiFile()
    midi.add_note(60, 0, 100)
    midi.add_note(62, 480, 100)
    
    # We inspect the raw bytes of the track to verify deltas
    # Track logic is internal, but we can verify via generated file size or content checks
    # For this test, we'll rely on the generated file parsing
    
    midi.save("output/test_rhythm.mid")
    
    with open("output/test_rhythm.mid", "rb") as f:
        data = f.read()
        
    # Find MTrk
    idx = data.find(b'MTrk')
    assert idx != -1
    
    track_data = data[idx+8:]
    
    # First event: Note On 60 at tick 0
    # Delta 0 (00), Note On ch1 (90), Pitch 60 (3C), Vel 64 (40)
    # Expected: 00 90 3C 40
    assert track_data.startswith(b'\x00\x90\x3C\x40')
    
    # Consume first event (4 bytes)
    offset = 4
    
    # Second event: Note Off 60 at tick 100
    # Delta: 100 - 0 = 100 (0x64) -> VLQ 64
    # Event: 80 3C 00
    # Expected: 64 80 3C 00
    assert track_data[offset:offset+4] == b'\x64\x80\x3C\x00'
    offset += 4
    
    # Third event: Note On 62 at tick 480
    # Previous tick: 100. Current tick: 480.
    # Delta: 480 - 100 = 380.
    # 380 in VLQ: 380 = 0x17C = 10 111 1100
    # Chunks: 010 (2), 1111100 (124/0x7C)
    # Byte 1: 2 | 0x80 = 0x82. Byte 2: 0x7C.
    # Expected: 82 7C 90 3E 40
    # If bug exists (using absolute 480): 480 -> 83 60
    assert track_data[offset:offset+2] == b'\x82\x7C'

def test_end_of_track_marker():
    midi = MidiFile()
    midi.add_note(60, 0, 480)
    midi.save("output/test_eot.mid")
    
    with open("output/test_eot.mid", "rb") as f:
        data = f.read()
    
    # Check last 3 bytes
    assert data[-3:] == b'\xFF\x2F\x00', "Missing End of Track marker (FF 2F 00)"
EOF

# 4. Set Ownership and Permissions
chown -R ga:ga "$PROJECT_DIR"

# 5. Record Start Time
date +%s > /tmp/task_start_time

# 6. Launch PyCharm
echo "Launching PyCharm..."
su - ga -c "DISPLAY=:1 nohup /opt/pycharm/bin/pycharm.sh '$PROJECT_DIR' > /tmp/pycharm_startup.log 2>&1 &"

# Wait for PyCharm
wait_for_pycharm 120

# Handle dialogs
dismiss_dialogs 5
handle_trust_dialog 5
focus_pycharm_window

# Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="