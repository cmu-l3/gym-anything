#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix G-Code Post-Processor Task ==="

WORKSPACE="/home/ga/workspace/gcode_processor"
sudo -u ga mkdir -p "$WORKSPACE/tests"
sudo -u ga mkdir -p "$WORKSPACE/data"

# Create hidden ground truth directory
mkdir -p /var/lib/app/ground_truth
chmod 700 /var/lib/app/ground_truth

# ──────────────────────────────────────────────────────────
# 1. Write the Buggy Code
# ──────────────────────────────────────────────────────────

cat > "$WORKSPACE/parser.py" << 'EOF'
import re

def parse_line(line):
    """Parses a G-code line into a dictionary of commands."""
    original_line = line
    
    # BUG 1: Blindly splitting by ';' strips out ';' inside string/paren comments
    # e.g., G0 X10 (MSG, "Wait; pause here") -> becomes G0 X10 (MSG, "Wait
    if ';' in line:
        line = line.split(';')[0]
        
    # Remove standard G-code inline parenthesis comments
    line = re.sub(r'\(.*?\)', '', line)
    line = line.strip()
    
    if not line:
        return None
        
    tokens = line.split()
    block = {}
    for token in tokens:
        if len(token) > 0:
            key = token[0].upper()
            val_str = token[1:]
            try:
                # Basic float conversion
                val = float(val_str)
            except ValueError:
                val = val_str
            block[key] = val
    return block
EOF

cat > "$WORKSPACE/state_machine.py" << 'EOF'
class MachineState:
    """Tracks the modal state of the CNC machine."""
    def __init__(self):
        self.x = 0.0
        self.y = 0.0
        self.is_relative = False
        self.feedrate = 1000.0

    def update(self, block):
        # Update positioning mode
        if 'G' in block:
            if block['G'] == 90:
                self.is_relative = False
            elif block['G'] == 91:
                self.is_relative = True
                
        # BUG 2: Ignoring is_relative mode when updating coordinates
        if 'X' in block:
            self.x = block['X']
        if 'Y' in block:
            self.y = block['Y']
            
        if 'F' in block:
            self.feedrate = block['F']
EOF

cat > "$WORKSPACE/geometry.py" << 'EOF'
import math

def calculate_distance(start_x, start_y, end_x, end_y, block):
    """Calculates the physical distance of a move."""
    if 'G' in block and block['G'] in (2, 3):
        # Arc move (G02/G03)
        i = block.get('I', 0.0)
        j = block.get('J', 0.0)
        
        # BUG 3: Calculating straight line chord instead of arc length
        # Arc length should be radius * theta
        return math.hypot(end_x - start_x, end_y - start_y)
    else:
        # Linear move (G00/G01)
        return math.hypot(end_x - start_x, end_y - start_y)
EOF

cat > "$WORKSPACE/analyzer.py" << 'EOF'
from state_machine import MachineState
from geometry import calculate_distance

class ToolpathAnalyzer:
    def __init__(self):
        self.state = MachineState()
        self.total_time = 0.0

    def process_block(self, block):
        start_x = self.state.x
        start_y = self.state.y
        
        # BUG 4: Feedrate is modal (persists), but this resets it if missing
        feedrate = block.get('F', 1000.0)
        
        # Update state
        self.state.update(block)
        
        # Calculate time
        distance = calculate_distance(start_x, start_y, self.state.x, self.state.y, block)
        
        if feedrate > 0:
            self.total_time += distance / feedrate
EOF

cat > "$WORKSPACE/exporter.py" << 'EOF'
def export_block(block):
    """Formats a block dictionary back into a G-code string."""
    parts = []
    
    # Ensure G is first if present
    if 'G' in block:
        # BUG 5: float formatting uses str() which can output scientific notation
        # e.g., 0.00005 -> "5e-05", which crashes the CNC controller
        parts.append(f"G{int(block['G']):02d}")
        
    for key, val in block.items():
        if key == 'G':
            continue
        if isinstance(val, float):
            # Should be formatted to fixed 4 decimal places without 'e'
            parts.append(f"{key}{str(val)}")
        else:
            parts.append(f"{key}{val}")
            
    return " ".join(parts)
EOF

cat > "$WORKSPACE/main.py" << 'EOF'
import sys
from parser import parse_line
from analyzer import ToolpathAnalyzer
from exporter import export_block

def main(input_file, output_file):
    analyzer = ToolpathAnalyzer()
    
    with open(input_file, 'r') as f_in, open(output_file, 'w') as f_out:
        for line in f_in:
            block = parse_line(line)
            if block:
                analyzer.process_block(block)
                f_out.write(export_block(block) + '\n')
                
    print(f"Total estimated time: {analyzer.total_time:.4f} minutes")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python main.py <input.gcode> <output.gcode>")
        sys.exit(1)
    main(sys.argv[1], sys.argv[2])
EOF

# ──────────────────────────────────────────────────────────
# 2. Write the Test Suite
# ──────────────────────────────────────────────────────────

cat > "$WORKSPACE/tests/test_comment_parsing.py" << 'EOF'
from parser import parse_line

def test_inline_semicolon_in_string():
    block = parse_line('G01 X10.5 (MSG, "Wait; pause tool") ; end line comment')
    assert block == {'G': 1.0, 'X': 10.5}

def test_standard_comment():
    block = parse_line('G00 Y50 ; move to safe height')
    assert block == {'G': 0.0, 'Y': 50.0}
EOF

cat > "$WORKSPACE/tests/test_positioning_modes.py" << 'EOF'
from state_machine import MachineState

def test_relative_positioning():
    state = MachineState()
    state.update({'G': 90.0, 'X': 10.0, 'Y': 10.0})
    assert state.x == 10.0
    
    state.update({'G': 91.0, 'X': 5.0, 'Y': -2.0})
    assert state.x == 15.0
    assert state.y == 8.0
    
    state.update({'G': 90.0, 'X': 0.0})
    assert state.x == 0.0
EOF

cat > "$WORKSPACE/tests/test_arc_geometry.py" << 'EOF'
import math
from geometry import calculate_distance

def test_quarter_circle_arc_length():
    # Start at (0, 10), center is at (0, 0) relative to start -> I=0, J=-10
    # End at (10, 0)
    # This is a quarter circle of radius 10. 
    # Arc length = 2 * pi * 10 / 4 = 15.70796
    dist = calculate_distance(0, 10, 10, 0, {'G': 2.0, 'I': 0.0, 'J': -10.0})
    assert math.isclose(dist, 15.70796, rel_tol=0.01)
EOF

cat > "$WORKSPACE/tests/test_modal_state.py" << 'EOF'
from analyzer import ToolpathAnalyzer
import math

def test_modal_feedrate():
    analyzer = ToolpathAnalyzer()
    analyzer.process_block({'G': 1.0, 'X': 10.0, 'F': 10.0}) # distance 10, feed 10 -> time 1.0
    analyzer.process_block({'G': 1.0, 'X': 20.0})            # distance 10, feed should remain 10 -> time 1.0
    assert math.isclose(analyzer.total_time, 2.0, rel_tol=0.01)
EOF

cat > "$WORKSPACE/tests/test_number_formatting.py" << 'EOF'
from exporter import export_block

def test_scientific_notation_avoided():
    block = {'G': 1.0, 'X': 0.00005, 'Y': 10.123456}
    result = export_block(block)
    assert 'e' not in result.lower()
    assert 'X0.0000' in result or 'X0.0001' in result
    assert 'Y10.1234' in result or 'Y10.1235' in result
EOF

# ──────────────────────────────────────────────────────────
# 3. Generate Ground Truth G-code File
# ──────────────────────────────────────────────────────────
echo "Generating complex G-code test file..."

cat > /tmp/generate_gcode.py << 'EOF'
import random
import math

def generate_toolpath(filename):
    with open(filename, 'w') as f:
        f.write("G90 ; Absolute positioning\n")
        f.write("G00 X0 Y0 F2000\n")
        f.write("(MSG, \"Start; Job\")\n")
        
        x, y = 0.0, 0.0
        feed = 2000
        
        for i in range(10000):
            if i % 100 == 0:
                feed = random.choice([500, 1000, 1500, 2000])
                f.write(f"G01 X{x:.4f} Y{y:.4f} F{feed}\n")
                
            cmd = random.choices(['G01', 'G02', 'G91', 'TINY'], weights=[0.6, 0.2, 0.1, 0.1])[0]
            
            if cmd == 'G01':
                nx = x + random.uniform(-10, 10)
                ny = y + random.uniform(-10, 10)
                f.write(f"G01 X{nx:.4f} Y{ny:.4f}\n")
                x, y = nx, ny
            elif cmd == 'G02':
                # Arc quarter circle
                r = random.uniform(5, 20)
                i_val = r
                j_val = 0
                nx = x + r
                ny = y - r
                f.write(f"G02 X{nx:.4f} Y{ny:.4f} I{i_val:.4f} J{j_val:.4f}\n")
                x, y = nx, ny
            elif cmd == 'G91':
                f.write("G91\n")
                dx = random.uniform(-5, 5)
                dy = random.uniform(-5, 5)
                f.write(f"G01 X{dx:.4f} Y{dy:.4f}\n")
                x, y = x + dx, y + dy
                f.write("G90\n")
            elif cmd == 'TINY':
                nx = x + 0.00005
                f.write(f"G01 X{nx:.8f}\n")
                x = nx

generate_toolpath("/var/lib/app/ground_truth/complex_part.gcode")
EOF
python3 /tmp/generate_gcode.py
cp /var/lib/app/ground_truth/complex_part.gcode "$WORKSPACE/data/sample_toolpath.gcode"

# ──────────────────────────────────────────────────────────
# 4. Calculate Expected Ground Truth Time
# ──────────────────────────────────────────────────────────
echo "Calculating correct expected time..."

cat > /tmp/calc_gt.py << 'EOF'
import math, re

def calculate_exact_time(filename):
    x, y = 0.0, 0.0
    is_rel = False
    feed = 1000.0
    time = 0.0
    
    with open(filename, 'r') as f:
        for line in f:
            line = line.split(';')[0]
            line = re.sub(r'\(.*?\)', '', line).strip()
            if not line: continue
            
            block = {}
            for t in line.split():
                try: block[t[0].upper()] = float(t[1:])
                except: pass
                
            if 'G' in block:
                if block['G'] == 90: is_rel = False
                if block['G'] == 91: is_rel = True
                
            if 'F' in block: feed = block['F']
            
            sx, sy = x, y
            
            if 'X' in block: x = x + block['X'] if is_rel else block['X']
            if 'Y' in block: y = y + block['Y'] if is_rel else block['Y']
            
            if 'G' in block and block['G'] in (2, 3):
                i_v = block.get('I', 0.0)
                j_v = block.get('J', 0.0)
                r = math.hypot(i_v, j_v)
                if r > 0:
                    # Chord
                    chord = math.hypot(x - sx, y - sy)
                    # Clamping to avoid domain error
                    val = max(-1.0, min(1.0, chord / (2*r)))
                    theta = 2 * math.asin(val)
                    dist = r * theta
                else:
                    dist = math.hypot(x - sx, y - sy)
            else:
                dist = math.hypot(x - sx, y - sy)
                
            if feed > 0: time += dist / feed
            
    with open('/var/lib/app/ground_truth/expected_time.txt', 'w') as out:
        out.write(f"{time:.4f}")

calculate_exact_time("/var/lib/app/ground_truth/complex_part.gcode")
EOF
python3 /tmp/calc_gt.py

chown -R ga:ga "$WORKSPACE"

# ──────────────────────────────────────────────────────────
# 5. Launch VS Code
# ──────────────────────────────────────────────────────────
echo "Recording start time..."
date +%s > /tmp/task_start_time.txt

echo "Starting VS Code..."
su - ga -c "DISPLAY=:1 code $WORKSPACE"
sleep 5

# Ensure window is maximized
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="