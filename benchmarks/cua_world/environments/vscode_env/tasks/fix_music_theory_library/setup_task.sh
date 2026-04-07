#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix Music Theory Library Task ==="

WORKSPACE_DIR="/home/ga/workspace/music_theory_lib"
sudo -u ga mkdir -p "$WORKSPACE_DIR/music_theory"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"
cd "$WORKSPACE_DIR"

# ──────────────────────────────────────────────
# 1. Base Note Class (Correct)
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/music_theory/note.py" << 'PYEOF'
class Note:
    """Represents a musical note with a name and octave."""
    
    # Base pitch classes (C = 0)
    PITCH_CLASSES = {
        'C': 0, 'C#': 1, 'Db': 1, 'D': 2, 'D#': 3, 'Eb': 3, 
        'E': 4, 'F': 5, 'F#': 6, 'Gb': 6, 'G': 7, 'G#': 8, 
        'Ab': 8, 'A': 9, 'A#': 10, 'Bb': 10, 'B': 11
    }

    def __init__(self, name, octave):
        self.name = name
        self.octave = octave
        if name not in self.PITCH_CLASSES:
            raise ValueError(f"Invalid note name: {name}")
        self.pitch_class = self.PITCH_CLASSES[name]

    def __repr__(self):
        return f"{self.name}{self.octave}"
PYEOF

# ──────────────────────────────────────────────
# 2. Bug 1: interval_calculator.py (Missing mod 12)
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/music_theory/interval_calculator.py" << 'PYEOF'
def interval_semitones(note1, note2):
    """
    Returns the shortest ascending interval in semitones between two notes.
    For example, from C to A should be 9 semitones.
    """
    # BUG: Missing % 12 to handle wrap-around (e.g. C to A gives -3 instead of 9)
    return note2.pitch_class - note1.pitch_class
PYEOF

# ──────────────────────────────────────────────
# 3. Bug 2 & 3: chord_analyzer.py (String comp & Inversion comp)
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/music_theory/chord_analyzer.py" << 'PYEOF'
class Chord:
    def __init__(self, root, chord_type):
        self.root = root  # Note object
        self.chord_type = chord_type  # string (e.g., 'major')

def detect_chord(notes):
    """Detects a chord from a list of Note objects."""
    # BUG 2: Uses string comparison (names) instead of pitch classes. 
    # This breaks enharmonic equivalence (e.g., Db won't match C#).
    note_names = sorted([n.name for n in notes])
    
    # Dictionary uses sharp spellings
    voicings = {
        "C major": sorted(["C", "E", "G"]),
        "Db major": sorted(["C#", "F", "G#"]),
        "D major": sorted(["D", "F#", "A"]),
    }
    
    for name, voicing in voicings.items():
        if note_names == voicing:
            return name
    return "Unknown"

def detect_inversion(chord, bass_note):
    """Detects the inversion of a chord given the bass note."""
    # BUG 3: Compares bass_note.name to chord.chord_type (string "major") 
    # instead of checking against the chord's root pitch class.
    if bass_note.name == chord.chord_type:
        return "root position"
    elif bass_note.pitch_class == (chord.root.pitch_class + 4) % 12:
        return "first inversion"
    elif bass_note.pitch_class == (chord.root.pitch_class + 7) % 12:
        return "second inversion"
    
    return "unknown"
PYEOF

# ──────────────────────────────────────────────
# 4. Bug 4: key_detector.py (Wrong direction for flats)
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/music_theory/key_detector.py" << 'PYEOF'
def detect_flat_key(num_flats):
    """Returns the pitch class of the major key with the given number of flats."""
    current = 0  # C major is pitch class 0
    for _ in range(num_flats):
        # BUG 4: +7 moves clockwise (sharp direction) around the circle of fifths.
        # Flat keys should move counter-clockwise (+5 or -7).
        current = (current + 7) % 12
    return current
PYEOF

# ──────────────────────────────────────────────
# 5. Bug 5: transposer.py (Octave boundary copy)
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/music_theory/transposer.py" << 'PYEOF'
from music_theory.note import Note

PITCH_CLASSES = {
    0: 'C', 1: 'C#', 2: 'D', 3: 'D#', 4: 'E', 5: 'F', 
    6: 'F#', 7: 'G', 8: 'G#', 9: 'A', 10: 'A#', 11: 'B'
}

def transpose(note, semitones_up):
    """Transposes a note up or down by a given number of semitones."""
    new_pc = (note.pitch_class + semitones_up) % 12
    new_name = PITCH_CLASSES[new_pc]
    
    # BUG 5: Octave boundary not recalculated. It just copies the old octave.
    # E.g., Transposing B4 up 1 semitone returns C4 instead of C5.
    new_octave = note.octave
    
    return Note(new_name, new_octave)
PYEOF

# ──────────────────────────────────────────────
# 6. Test Suite
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/tests/test_music_theory.py" << 'PYEOF'
import pytest
from music_theory.note import Note
from music_theory.interval_calculator import interval_semitones
from music_theory.chord_analyzer import Chord, detect_chord, detect_inversion
from music_theory.key_detector import detect_flat_key
from music_theory.transposer import transpose

def test_interval_wrap_around():
    # C to A is a major 6th (9 semitones)
    assert interval_semitones(Note('C', 4), Note('A', 4)) == 9
    # F to D is a major 6th (9 semitones)
    assert interval_semitones(Note('F', 4), Note('D', 5)) == 9

def test_enharmonic_chord_recognition():
    # Db, F, Ab is enharmonically C#, E#, G# (Db major)
    notes = [Note('Db', 4), Note('F', 4), Note('Ab', 4)]
    assert detect_chord(notes) == "Db major"

def test_chord_inversion():
    c_major = Chord(Note('C', 4), 'major')
    # Root position: C is in the bass
    assert detect_inversion(c_major, Note('C', 2)) == "root position"
    # First inversion: E is in the bass
    assert detect_inversion(c_major, Note('E', 2)) == "first inversion"

def test_flat_key_detection():
    # 1 flat (Bb) -> F major (pitch class 5)
    assert detect_flat_key(1) == 5
    # 3 flats (Bb, Eb, Ab) -> Eb major (pitch class 3)
    assert detect_flat_key(3) == 3

def test_octave_transposition():
    # B4 up 1 semitone is C5
    assert transpose(Note('B', 4), 1).octave == 5
    # C5 down 1 semitone is B4
    assert transpose(Note('C', 5), -1).octave == 4
    # G4 up 12 semitones is G5
    assert transpose(Note('G', 4), 12).octave == 5
PYEOF

# Create init files
sudo -u ga touch "$WORKSPACE_DIR/music_theory/__init__.py"
sudo -u ga touch "$WORKSPACE_DIR/tests/__init__.py"

# Write README
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Music Theory Library

This library provides core domain logic for our music technology applications.
Recently, several bugs have been reported in the interval, chord, key, and transposition modules. 

Please run the test suite using:
`python3 -m pytest tests/ -v`

Fix all failing tests so the pipeline can proceed to integration. 
Do NOT modify the test files themselves—only the library code in `/music_theory`.
EOF

# Ensure permissions
chown -R ga:ga "$WORKSPACE_DIR"

# Install pytest
echo "Installing pytest..."
pip3 install pytest > /dev/null 2>&1

# Record start time
date +%s > /tmp/task_start_time.txt

# Start VS Code
echo "Starting VS Code..."
sudo -u ga code "$WORKSPACE_DIR" > /tmp/vscode_launch.log 2>&1 &
sleep 5

# Focus VS Code window
focus_vscode_window 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Setup Complete ==="