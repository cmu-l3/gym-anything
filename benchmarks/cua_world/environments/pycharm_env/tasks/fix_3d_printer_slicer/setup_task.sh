#!/bin/bash
echo "=== Setting up fix_3d_printer_slicer task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/PycharmProjects/py_slicer"
DATA_DIR="$PROJECT_DIR/data"
SRC_DIR="$PROJECT_DIR/py_slicer"
TEST_DIR="$PROJECT_DIR/tests"

# Clean previous run
rm -rf "$PROJECT_DIR"
rm -f /tmp/fix_3d_printer_slicer_result.json /tmp/fix_3d_printer_slicer_start_ts

# Create directories
su - ga -c "mkdir -p '$DATA_DIR' '$SRC_DIR' '$TEST_DIR'"

# ------------------------------------------------------------------
# 1. Generate STL Data (Cube and Pyramid)
# ------------------------------------------------------------------
cat > "$DATA_DIR/generate_stls.py" << 'PYEOF'
import struct

def write_ascii_stl(filename, name, triangles):
    with open(filename, 'w') as f:
        f.write(f"solid {name}\n")
        for v1, v2, v3 in triangles:
            # Normal (dummy)
            f.write("  facet normal 0 0 0\n")
            f.write("    outer loop\n")
            for v in [v1, v2, v3]:
                f.write(f"      vertex {v[0]:.6f} {v[1]:.6f} {v[2]:.6f}\n")
            f.write("    endloop\n")
            f.write("  endfacet\n")
        f.write(f"endsolid {name}\n")

# Cube (10x10x10)
cube_tris = []
# Z=0 face (2 tris)
cube_tris.append(((0,0,0), (10,0,0), (10,10,0)))
cube_tris.append(((0,0,0), (10,10,0), (0,10,0)))
# Z=10 face
cube_tris.append(((0,0,10), (10,10,10), (10,0,10)))
cube_tris.append(((0,0,10), (0,10,10), (10,10,10)))
# Side faces (simplified for brevity, just ensuring we have height)
cube_tris.append(((0,0,0), (0,10,0), (0,10,10))) # X=0
cube_tris.append(((0,0,0), (0,10,10), (0,0,10)))
cube_tris.append(((10,0,0), (10,0,10), (10,10,10))) # X=10
cube_tris.append(((10,0,0), (10,10,10), (10,10,0)))
cube_tris.append(((0,0,0), (0,0,10), (10,0,10))) # Y=0
cube_tris.append(((0,0,0), (10,0,10), (10,0,0)))
cube_tris.append(((0,10,0), (10,10,0), (10,10,10))) # Y=10
cube_tris.append(((0,10,0), (10,10,10), (0,10,10)))

write_ascii_stl('data/cube.stl', 'cube', cube_tris)

# Pyramid (Base 10x10 at Z=0, Tip at 5,5,10)
# Has horizontal edges at Z=0
pyramid_tris = []
# Base
pyramid_tris.append(((0,0,0), (10,0,0), (10,10,0)))
pyramid_tris.append(((0,0,0), (10,10,0), (0,10,0)))
# Sides
tip = (5,5,10)
pyramid_tris.append(((0,0,0), (0,10,0), tip))
pyramid_tris.append(((0,10,0), (10,10,0), tip))
pyramid_tris.append(((10,10,0), (10,0,0), tip))
pyramid_tris.append(((10,0,0), (0,0,0), tip))

write_ascii_stl('data/pyramid.stl', 'pyramid', pyramid_tris)
PYEOF

cd "$PROJECT_DIR" && python3 data/generate_stls.py
rm "$DATA_DIR/generate_stls.py"

# ------------------------------------------------------------------
# 2. Source Code (Buggy)
# ------------------------------------------------------------------

# __init__.py
touch "$SRC_DIR/__init__.py"

# stl_reader.py (Correct)
cat > "$SRC_DIR/stl_reader.py" << 'PYEOF'
import re

class Mesh:
    def __init__(self):
        self.triangles = []  # List of (v1, v2, v3) tuples, where v is (x,y,z)

    def add_triangle(self, v1, v2, v3):
        self.triangles.append((v1, v2, v3))

def read_stl(filepath):
    mesh = Mesh()
    with open(filepath, 'r') as f:
        content = f.read()
    
    # Simple regex parser for ASCII STL
    vertex_pattern = r'vertex\s+([-\d\.eE]+)\s+([-\d\.eE]+)\s+([-\d\.eE]+)'
    vertices = re.findall(vertex_pattern, content)
    
    coords = [(float(v[0]), float(v[1]), float(v[2])) for v in vertices]
    
    for i in range(0, len(coords), 3):
        if i + 2 < len(coords):
            mesh.add_triangle(coords[i], coords[i+1], coords[i+2])
            
    return mesh
PYEOF

# engine.py (BUGGY)
cat > "$SRC_DIR/engine.py" << 'PYEOF'
import math

class SlicerEngine:
    def __init__(self, mesh):
        self.mesh = mesh

    def slice_at_height(self, z_height):
        """Returns a list of line segments [(p1, p2), ...] for a given Z height."""
        segments = []
        for tri in self.mesh.triangles:
            # Check if triangle intersects z_height
            zs = [v[2] for v in tri]
            if min(zs) > z_height or max(zs) < z_height:
                continue
            
            # Find intersection segment
            points = []
            # Check edges (0-1, 1-2, 2-0)
            for i in range(3):
                p1 = tri[i]
                p2 = tri[(i+1)%3]
                
                z1 = p1[2]
                z2 = p2[2]
                
                # Check if edge crosses plane
                if (z1 <= z_height <= z2) or (z2 <= z_height <= z1):
                    # BUG 1: Horizontal edge crash (ZeroDivisionError if z1 == z2)
                    # If an edge lies exactly on the plane, we ignore it for now or handle it naively
                    # But the calculation below crashes if z2 == z1
                    t = (z_height - z1) / (z2 - z1)
                    
                    x = p1[0] + t * (p2[0] - p1[0])
                    y = p1[1] + t * (p2[1] - p1[1])
                    points.append((x, y))
            
            if len(points) == 2:
                segments.append((points[0], points[1]))
        
        return self.chain_segments(segments)

    def generate_layers(self, layer_height, max_z):
        """Generates slices from 0 to max_z."""
        layers = {}
        current_z = layer_height
        
        # BUG 2: Missing top layer
        # Floating point comparison 'current_z < max_z' often stops 1 layer early
        # e.g., if max_z=10 and current_z reaches 10.0, 10.0 < 10.0 is False
        while current_z < max_z:
            layers[current_z] = self.slice_at_height(current_z)
            current_z += layer_height
            
        return layers

    def chain_segments(self, segments):
        """Connects line segments into closed polygons."""
        if not segments:
            return []
            
        # Naive chaining logic
        polygons = []
        # In a real implementation this is complex, here we use a simplified greedy approach
        # for the sake of the exercise
        
        # BUG 3: Open loops
        # This function returns a list of points. It fails to verify if the 
        # final point connects back to the start point within tolerance.
        
        ordered_points = []
        if segments:
            current_seg = segments[0]
            ordered_points.append(current_seg[0])
            ordered_points.append(current_seg[1])
            # (Simplified: assumes segments are somewhat ordered or we just take one loop for the task)
            # A real fix would require robust topology reconstruction.
            # For this task, let's assume the test checks if ordered_points[0] approx equals ordered_points[-1]
            
            # The bug is that we don't force closure or check it
            pass 
            
        return ordered_points

def distance(p1, p2):
    return math.sqrt((p1[0]-p2[0])**2 + (p1[1]-p2[1])**2)
PYEOF

# ------------------------------------------------------------------
# 3. Tests
# ------------------------------------------------------------------

cat > "$TEST_DIR/conftest.py" << 'PYEOF'
import pytest
import os
import sys

# Add project root to path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from py_slicer.stl_reader import read_stl

@pytest.fixture
def cube_mesh():
    return read_stl('data/cube.stl')

@pytest.fixture
def pyramid_mesh():
    return read_stl('data/pyramid.stl')
PYEOF

cat > "$TEST_DIR/test_slicing.py" << 'PYEOF'
import pytest
from py_slicer.engine import SlicerEngine

def test_horizontal_intersection(pyramid_mesh):
    """
    Bug 1: Slicing at Z=0 where the pyramid base edges are horizontal.
    Should NOT raise ZeroDivisionError.
    """
    engine = SlicerEngine(pyramid_mesh)
    try:
        # The base is at Z=0. If we slice exactly at 0, or very close, horizontal edges appear
        # We test slightly above 0 to hit the edge processing logic if it considers edges crossing
        # But specifically, if we test a Z that matches a vertex exactly, z1 or z2 might match height
        # Let's force a horizontal edge case check by slicing exactly at a vertex Z if possible,
        # or relying on the engine logic that processes edges.
        # Actually, let's simulate the condition: pass a mesh with a known horizontal edge at slice height.
        # The engine logic 'if (z1 <= z_height <= z2)' captures horizontal edges if z1=z2=z_height.
        # Then (z_height - z1) / (z2 - z1) becomes 0/0.
        
        # Slice exactly at Z=0 where base exists
        result = engine.slice_at_height(0.0)
        assert len(result) > 0
    except ZeroDivisionError:
        pytest.fail("Slicer crashed on horizontal edge (ZeroDivisionError)")

def test_layer_count(cube_mesh):
    """
    Bug 2: Generate layers for a 10mm tall cube with 1mm layer height.
    Should produce 10 layers (at 1, 2, ..., 10).
    Currently produces 9 because 10.0 < 10.0 is False.
    """
    engine = SlicerEngine(cube_mesh)
    layers = engine.generate_layers(layer_height=1.0, max_z=10.0)
    
    # We expect layers at Z=1.0, 2.0, ... 10.0
    # Depending on start (current_z = layer_height), 10.0 should be included.
    assert 10.0 in layers, "Top layer (Z=10.0) is missing!"
    assert len(layers) == 10, f"Expected 10 layers, got {len(layers)}"

def test_perimeter_closure(cube_mesh):
    """
    Bug 3: The resulting polygon points must form a closed loop.
    First point should equal last point (or be connected).
    For this simplified engine, we expect the output list to include the closing point
    or satisfy a closure check.
    """
    engine = SlicerEngine(cube_mesh)
    # Slice at mid-height
    points = engine.slice_at_height(5.0)
    
    if not points:
        pytest.fail("No points generated for slice")
        
    p_start = points[0]
    p_end = points[-1]
    
    dist = ((p_start[0]-p_end[0])**2 + (p_start[1]-p_end[1])**2)**0.5
    
    # In a proper slicer, points are usually unique vertices of the poly. 
    # But usually 'chain_segments' logic ensures the loop is logically closed.
    # Here we assert that the gap is effectively closed or explicit start==end
    # Since the buggy code just dumps segments, it likely leaves a gap or duplicate points
    # without closing the loop topology.
    
    # We enforce that the logic explicitly closes the loop (dist < epsilon)
    assert dist < 1e-5, f"Polygon is open! Gap distance: {dist}"

PYEOF

# requirements.txt
echo "pytest" > "$PROJECT_DIR/requirements.txt"

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Timestamp start
date +%s > /tmp/fix_3d_printer_slicer_start_ts

# Launch PyCharm
source /workspace/scripts/task_utils.sh
setup_pycharm_project "$PROJECT_DIR" "py_slicer" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="