#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Repair CIF Parser Task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

WORKSPACE_DIR="/home/ga/workspace/cif_parser"
sudo -u ga mkdir -p "$WORKSPACE_DIR/cif_parser"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data"

# 1. Create parser.py with Bugs 1, 2, 3, 4
cat > "$WORKSPACE_DIR/cif_parser/parser.py" << 'EOF'
import re

def clean_float(val):
    """Convert CIF string to float."""
    # BUG 1: Crashes on values with standard uncertainty like '10.5(2)'
    return float(val)

def parse_metadata(content):
    """Extract global metadata from CIF."""
    metadata = {}
    # BUG 4: Fails to match multiline key-values. Uses [ \t]+ instead of \s+
    matches = re.findall(r'(_[a-zA-Z0-9_-]+)[ \t]+([^_\s][^\n]*)', content)
    for k, v in matches:
        # BUG 2: Doesn't strip surrounding quotes from strings
        metadata[k] = v.strip()
    return metadata

def parse_atoms(content):
    """Parse atom coordinates from the loop block."""
    atoms = []
    loop_pattern = r'loop_[\s\S]*?(?=\n\s*loop_|\n\s*_|\Z)'
    loops = re.findall(loop_pattern, content)
    
    for loop in loops:
        if '_atom_site_fract_x' in loop:
            lines = loop.strip().split('\n')
            headers = [l.strip() for l in lines if l.strip().startswith('_atom_site_')]
            data_lines = [l.strip() for l in lines if l.strip() and not l.strip().startswith('_')]
            
            for line in data_lines:
                parts = line.split()
                # BUG 3: Hardcoded indices. Should dynamically look up using `headers.index()`
                if len(parts) >= 5:
                    label = parts[0]
                    x = clean_float(parts[2])
                    y = clean_float(parts[3])
                    z = clean_float(parts[4])
                    atoms.append({'label': label, 'x': x, 'y': y, 'z': z})
    return atoms
EOF

# 2. Create geometry.py with Bug 5
cat > "$WORKSPACE_DIR/cif_parser/geometry.py" << 'EOF'
import math

def calculate_bond_distance(atom1, atom2, cell_a, cell_b, cell_c):
    """
    Calculate distance between two fractional coordinates in an orthogonal unit cell.
    Returns the shortest distance considering periodic boundary conditions.
    """
    dx = atom1['x'] - atom2['x']
    dy = atom1['y'] - atom2['y']
    dz = atom1['z'] - atom2['z']
    
    # BUG 5: Missing periodic boundary condition wrapping
    # Should wrap fractional differences to [-0.5, 0.5] range before multiplying by cell lengths
    # e.g., dx -= round(dx)
    
    dist = math.sqrt((dx * cell_a)**2 + (dy * cell_b)**2 + (dz * cell_c)**2)
    return dist
EOF

# 3. Create __init__.py
touch "$WORKSPACE_DIR/cif_parser/__init__.py"

# 4. Create the Test Suite
cat > "$WORKSPACE_DIR/tests/test_parser.py" << 'EOF'
import pytest
from cif_parser.parser import clean_float, parse_metadata, parse_atoms
from cif_parser.geometry import calculate_bond_distance

def test_clean_float():
    assert clean_float("1.23") == 1.23
    assert clean_float("5.4309(4)") == 5.4309  # Should strip uncertainty

def test_parse_metadata_quotes():
    content = "_symmetry_space_group_name_H-M   'P m -3 m'\n_cell_volume 150.5"
    meta = parse_metadata(content)
    assert meta.get("_symmetry_space_group_name_H-M") == "P m -3 m"  # Quotes stripped

def test_parse_metadata_multiline():
    content = "_cell_length_a\n10.5\n_cell_length_b\n10.5"
    meta = parse_metadata(content)
    assert meta.get("_cell_length_a") == "10.5"  # Should handle newlines

def test_parse_atoms_dynamic():
    content = """loop_
_atom_site_label
_atom_site_type_symbol
_atom_site_fract_x
_atom_site_fract_y
_atom_site_fract_z
_atom_site_occupancy
Si1 Si 0.25 0.50 0.75 1.0
"""
    atoms = parse_atoms(content)
    assert len(atoms) == 1
    assert atoms[0]['x'] == 0.25
    assert atoms[0]['y'] == 0.50
    assert atoms[0]['z'] == 0.75

def test_periodic_boundary():
    # Two atoms very close across the boundary
    a1 = {'x': 0.01, 'y': 0.5, 'z': 0.5}
    a2 = {'x': 0.99, 'y': 0.5, 'z': 0.5}
    dist = calculate_bond_distance(a1, a2, 10.0, 10.0, 10.0)
    # The actual physical distance is 0.2, not 9.8!
    assert abs(dist - 0.2) < 1e-6
EOF

# 5. Embed a real CIF sample (Silicon - COD ID 9008565)
cat > "$WORKSPACE_DIR/data/silicon.cif" << 'EOF'
data_9008565
_symmetry_space_group_name_H-M   'F d -3 m'
_cell_length_a   5.4309(4)
_cell_length_b   5.4309(4)
_cell_length_c   5.4309(4)
_cell_volume   160.18
loop_
_atom_site_label
_atom_site_fract_x
_atom_site_fract_y
_atom_site_fract_z
_atom_site_occupancy
Si1 0.0 0.0 0.0 1.00000
EOF

# Set permissions
chown -R ga:ga "$WORKSPACE_DIR"

# Ensure VSCode is open
if ! pgrep -f "code.*reconciliation" > /dev/null; then
    su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR &"
    sleep 5
fi

# Maximize and focus
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="