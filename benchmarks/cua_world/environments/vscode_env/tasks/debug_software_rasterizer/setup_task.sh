#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Debug Software Rasterizer Task ==="

WORKSPACE_DIR="/home/ga/workspace/tiny_rasterizer"
sudo -u ga mkdir -p "$WORKSPACE_DIR/assets"
cd "$WORKSPACE_DIR"

# ──────────────────────────────────────────────
# 1. Generate 3D Asset (Torus.obj)
# ──────────────────────────────────────────────
echo "Generating 3D asset..."
python3 << 'PYTORUS' > "$WORKSPACE_DIR/assets/torus.obj"
import math
R, r = 2.0, 0.8
seg_u, seg_v = 40, 30
for i in range(seg_u):
    u = i * 2 * math.pi / seg_u
    for j in range(seg_v):
        v = j * 2 * math.pi / seg_v
        x = (R + r * math.cos(v)) * math.cos(u)
        y = (R + r * math.cos(v)) * math.sin(u)
        z = r * math.sin(v)
        print(f"v {x} {y} {z}")
for i in range(seg_u):
    for j in range(seg_v):
        n1 = i * seg_v + j + 1
        n2 = i * seg_v + (j + 1) % seg_v + 1
        n3 = ((i + 1) % seg_u) * seg_v + (j + 1) % seg_v + 1
        n4 = ((i + 1) % seg_u) * seg_v + j + 1
        print(f"f {n1} {n2} {n3}")
        print(f"f {n1} {n3} {n4}")
PYTORUS

# ──────────────────────────────────────────────
# 2. Create Source Files (with injected bugs)
# ──────────────────────────────────────────────

cat > "$WORKSPACE_DIR/geometry.py" << 'EOF'
import numpy as np

def barycentric(A, B, C, P):
    """
    Calculate barycentric coordinates (w0, w1, w2) for point P in triangle ABC.
    Returns (-1, -1, -1) if the triangle is degenerate (zero area).
    """
    # BUG 4: Determinant calculation mixes up X and Y coordinates.
    # C[1] - A[0] is used instead of C[0] - A[0]
    denom = (B[0] - A[0]) * (C[1] - A[1]) - (C[1] - A[0]) * (B[1] - A[1])
    
    if abs(denom) < 1e-5:
        return -1, -1, -1
        
    w1 = ((P[0] - A[0]) * (C[1] - A[1]) - (C[0] - A[0]) * (P[1] - A[1])) / denom
    w2 = ((B[0] - A[0]) * (P[1] - A[1]) - (P[0] - A[0]) * (B[1] - A[1])) / denom
    w0 = 1.0 - w1 - w2
    
    return w0, w1, w2
EOF

cat > "$WORKSPACE_DIR/camera.py" << 'EOF'
import numpy as np

def perspective_divide(v):
    """
    Divides x, y, z by the homogeneous coordinate w for perspective projection.
    """
    # BUG 3: Fails to divide the z coordinate by w
    return np.array([v[0] / v[3], v[1] / v[3], v[2] / 1.0, 1.0])

def viewport_matrix(width, height):
    """
    Creates a viewport matrix mapping Normalized Device Coordinates (NDC) 
    to screen coordinates.
    """
    m = np.eye(4)
    m[0, 3] = width / 2.0
    m[1, 3] = height / 2.0
    m[2, 3] = 255 / 2.0
    
    m[0, 0] = width / 2.0
    # BUG 5: Y-axis should be inverted (negative) because image Y points down!
    m[1, 1] = height / 2.0  
    m[2, 2] = 255 / 2.0
    
    return m
EOF

cat > "$WORKSPACE_DIR/rasterizer.py" << 'EOF'
import numpy as np

def calculate_normal(A, B, C):
    """
    Calculates the surface normal vector for a triangle defined by A, B, C.
    """
    # BUG 1: Winding order swapped. Should be cross(B-A, C-A)
    edge1 = C - A
    edge2 = B - A
    n = np.cross(edge1, edge2)
    norm = np.linalg.norm(n)
    return n / norm if norm > 0 else n

def update_zbuffer(zbuffer, x, y, z):
    """
    Updates the Z-buffer and returns True if the new pixel is closer to the camera.
    Assumes standard positive depth (smaller Z is closer).
    """
    # BUG 2: Reversed depth test.
    if z > zbuffer[y, x]:
        zbuffer[y, x] = z
        return True
    return False
EOF

cat > "$WORKSPACE_DIR/render.py" << 'EOF'
import numpy as np
import cv2
import geometry, camera, rasterizer

def render(obj_file, output_file):
    width, height = 800, 800
    image = np.zeros((height, width, 3), dtype=np.uint8)
    zbuffer = np.full((height, width), np.inf)

    # Simple obj parser
    vertices, faces = [], []
    with open(obj_file, 'r') as f:
        for line in f:
            if line.startswith('v '):
                vertices.append([float(x) for x in line.split()[1:4]] + [1.0])
            elif line.startswith('f '):
                faces.append([int(x.split()[i].split('/')[0])-1 for i in range(1, 4)])

    vertices = np.array(vertices)
    vp = camera.viewport_matrix(width, height)
    
    # Simple setup: move object into view, light from front
    for i in range(len(vertices)):
        vertices[i][2] += 5.0
        
    light_dir = np.array([0, 0, -1])

    for face in faces:
        v0, v1, v2 = vertices[face[0]], vertices[face[1]], vertices[face[2]]
        
        # Face Normal & Intensity
        n = rasterizer.calculate_normal(v0[:3], v1[:3], v2[:3])
        intensity = -np.dot(n, light_dir)
        
        if intensity < 0:
            continue  # Backface cull
            
        # Project to screen
        p0 = vp @ camera.perspective_divide(v0)
        p1 = vp @ camera.perspective_divide(v1)
        p2 = vp @ camera.perspective_divide(v2)
        
        # Bounding box limits
        min_x = max(0, int(min(p0[0], p1[0], p2[0])))
        max_x = min(width-1, int(max(p0[0], p1[0], p2[0])))
        min_y = max(0, int(min(p0[1], p1[1], p2[1])))
        max_y = min(height-1, int(max(p0[1], p1[1], p2[1])))
        
        color = np.array([255, 200, 100]) * intensity
        
        # Rasterize triangle
        for y in range(min_y, max_y + 1):
            for x in range(min_x, max_x + 1):
                w0, w1, w2 = geometry.barycentric(p0, p1, p2, [x, y, 0])
                if w0 >= 0 and w1 >= 0 and w2 >= 0:
                    z = w0*p0[2] + w1*p1[2] + w2*p2[2]
                    if rasterizer.update_zbuffer(zbuffer, x, y, z):
                        image[y, x] = color
                        
    cv2.imwrite(output_file, image)

if __name__ == '__main__':
    render('assets/torus.obj', 'output.png')
    print("Rendered to output.png")
EOF

# ──────────────────────────────────────────────
# 3. Create Ground Truth Hidden Test Suite
# ──────────────────────────────────────────────
sudo mkdir -p /var/lib/app/ground_truth
cat > /var/lib/app/ground_truth/test_math.py << 'EOF'
import sys
import json
import numpy as np

# Load the agent's code dynamically
sys.path.insert(0, '/home/ga/workspace/tiny_rasterizer')
import geometry, camera, rasterizer

results = {}

# Test 1: Barycentric
try:
    A, B, C, P = [0,0,0], [10,0,0], [0,10,0], [2,2,0]
    w0, w1, w2 = geometry.barycentric(A, B, C, P)
    results['test_barycentric'] = bool(np.allclose([w0, w1, w2], [0.6, 0.2, 0.2]))
except Exception as e:
    results['test_barycentric'] = False

# Test 2: Perspective Divide
try:
    v = np.array([10.0, 20.0, 30.0, 2.0])
    out = camera.perspective_divide(v)
    results['test_perspective_divide'] = bool(np.allclose(out[:3], [5.0, 10.0, 15.0]))
except Exception as e:
    results['test_perspective_divide'] = False

# Test 3: Viewport Transform
try:
    vp = camera.viewport_matrix(800, 600)
    p1 = vp @ np.array([0, 1, 0, 1])
    # The Y axis must be inverted (NDC Y=1 maps to Screen Y=0)
    results['test_viewport_matrix'] = bool(np.allclose(p1[1]/p1[3], 0))
except Exception as e:
    results['test_viewport_matrix'] = False

# Test 4: Backface Culling (Normal calculation)
try:
    A, B, C = np.array([0,0,0]), np.array([1,0,0]), np.array([0,1,0])
    n = rasterizer.calculate_normal(A, B, C)
    results['test_normal_calculation'] = bool(n[2] > 0)
except Exception as e:
    results['test_normal_calculation'] = False

# Test 5: Z-Buffer Logic
try:
    zbuf = np.array([[10.0]])
    rasterizer.update_zbuffer(zbuf, 0, 0, 5.0)
    res1 = bool(zbuf[0,0] == 5.0)
    rasterizer.update_zbuffer(zbuf, 0, 0, 8.0)
    res2 = bool(zbuf[0,0] == 5.0) # Should NOT update, closer stays
    results['test_zbuffer_logic'] = res1 and res2
except Exception as e:
    results['test_zbuffer_logic'] = False

with open('/tmp/test_results.json', 'w') as f:
    json.dump(results, f)
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# ──────────────────────────────────────────────
# 4. Generate initial broken output & start timer
# ──────────────────────────────────────────────
echo "Running initial buggy render..."
sudo -u ga python3 "$WORKSPACE_DIR/render.py"
date +%s > /tmp/task_start_time.txt

# Focus VS Code
focus_vscode_window 2>/dev/null || true

# Screenshot initial state
take_screenshot /tmp/task_initial.png ga

echo "=== Task Setup Complete ==="