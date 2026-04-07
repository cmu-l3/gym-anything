#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up SVG Animation Generator Task ==="

WORKSPACE_DIR="/home/ga/workspace/svg_animator"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Create package structure
sudo -u ga mkdir -p animation svg tests examples

# ─────────────────────────────────────────────────────────────
# 1. Buggy Source Files
# ─────────────────────────────────────────────────────────────

cat > "$WORKSPACE_DIR/animation/__init__.py" << 'EOF'
EOF

cat > "$WORKSPACE_DIR/svg/__init__.py" << 'EOF'
EOF

cat > "$WORKSPACE_DIR/animation/interpolator.py" << 'EOF'
def cubic_bezier(t, p0, p1, p2, p3):
    """Calculate the position on a cubic bezier curve at time t (0.0 to 1.0)."""
    term0 = (1 - t)**3 * p0
    term1 = 3 * (1 - t)**2 * t * p2  # BUG: p2 instead of p1
    term2 = 3 * (1 - t) * t**2 * p1  # BUG: p1 instead of p2
    term3 = t**3 * p3
    return term0 + term1 + term2 + term3
EOF

cat > "$WORKSPACE_DIR/animation/color_utils.py" << 'EOF'
def hsl_to_rgb(h, s, l):
    """Convert HSL to RGB (0-255)."""
    h = h % 360
    s = max(0.0, min(1.0, s))
    l = max(0.0, min(1.0, l))
    
    c = (1 - abs(2 * l - 1)) * s
    x = c * (1 - abs((h / 60.0) % 2 - 1))
    m = l - c / 2.0
    
    sector = int(h / 60)
    
    # Map sector to RGB components
    if sector == 0:
        r1, g1, b1 = x, c, 0  # BUG: should be c, x, 0
    elif sector == 1:
        r1, g1, b1 = 0, c, x  # BUG: should be x, c, 0
    elif sector == 2:
        r1, g1, b1 = 0, x, c  # BUG: should be 0, c, x
    elif sector == 3:
        r1, g1, b1 = x, 0, c  # BUG: should be 0, x, c
    elif sector == 4:
        r1, g1, b1 = c, 0, x  # BUG: should be x, 0, c
    else:
        r1, g1, b1 = c, x, 0  # BUG: should be c, 0, x
        
    return (int((r1 + m) * 255), int((g1 + m) * 255), int((b1 + m) * 255))
EOF

cat > "$WORKSPACE_DIR/svg/path_builder.py" << 'EOF'
def arc_to(rx, ry, x_rot, large_arc_flag, sweep_flag, x, y):
    """Generate an SVG path arc command."""
    # Format: A rx ry x-axis-rotation large-arc-flag sweep-flag x y
    # BUG: sweep_flag and large_arc_flag are swapped in the output
    return f"A {rx} {ry} {x_rot} {sweep_flag} {large_arc_flag} {x} {y}"

def move_to(x, y):
    return f"M {x} {y}"

def line_to(x, y):
    return f"L {x} {y}"
EOF

cat > "$WORKSPACE_DIR/animation/timeline.py" << 'EOF'
def generate_frame_times(start_time, end_time, fps=30):
    """Generate a list of timestamps for each frame in the animation."""
    start_frame = int(start_time * fps)
    end_frame = int(end_time * fps)
    
    frames = []
    # BUG: range excludes end_frame, dropping the final keyframe
    for f in range(start_frame, end_frame):
        frames.append(f / fps)
    return frames
EOF

cat > "$WORKSPACE_DIR/svg/renderer.py" << 'EOF'
def render_svg(width, height, elements):
    """Wrap SVG elements in the standard SVG boilerplate."""
    # BUG: width and height are swapped in the viewBox attribute
    viewbox = f"0 0 {height} {width}"
    
    lines = [
        f'<svg width="{width}" height="{height}" viewBox="{viewbox}" xmlns="http://www.w3.org/2000/svg">'
    ]
    for el in elements:
        lines.append(f"  {el}")
    lines.append("</svg>")
    
    return "\n".join(lines)
EOF

cat > "$WORKSPACE_DIR/generate.py" << 'EOF'
import sys

def main():
    print("SVG Animation Generator v1.0")
    print("Run 'python3 -m pytest tests/' to verify components.")
    
if __name__ == "__main__":
    main()
EOF

# ─────────────────────────────────────────────────────────────
# 2. Test Suite (Hidden copy saved to prevent tampering)
# ─────────────────────────────────────────────────────────────

cat > "$WORKSPACE_DIR/tests/test_interpolator.py" << 'EOF'
import sys, os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from animation.interpolator import cubic_bezier

def test_cubic_bezier_asymmetric():
    # Asymmetric test to catch parameter swapping (p1 vs p2)
    # Correct formula should yield 4.375. If swapped, yields 1.5625.
    res = cubic_bezier(0.25, 0, 10, 0, 10)
    assert abs(res - 4.375) < 0.001, f"Expected 4.375, got {res}"
EOF

cat > "$WORKSPACE_DIR/tests/test_color_utils.py" << 'EOF'
import sys, os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from animation.color_utils import hsl_to_rgb

def test_hsl_to_rgb_red():
    # Hue 0 -> Red
    r, g, b = hsl_to_rgb(0, 1.0, 0.5)
    assert (r, g, b) == (255, 0, 0), f"Expected (255, 0, 0), got {(r, g, b)}"

def test_hsl_to_rgb_blue():
    # Hue 240 -> Blue
    r, g, b = hsl_to_rgb(240, 1.0, 0.5)
    assert (r, g, b) == (0, 0, 255), f"Expected (0, 0, 255), got {(r, g, b)}"
EOF

cat > "$WORKSPACE_DIR/tests/test_path_builder.py" << 'EOF'
import sys, os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from svg.path_builder import arc_to

def test_arc_to_flag_order():
    res = arc_to(10, 15, 0, 1, 0, 20, 20)
    # W3C Spec: A rx ry x-rot large_arc sweep x y
    assert res == "A 10 15 0 1 0 20 20", f"Output arc command incorrect: {res}"
EOF

cat > "$WORKSPACE_DIR/tests/test_timeline.py" << 'EOF'
import sys, os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from animation.timeline import generate_frame_times

def test_generate_frame_times():
    # 0.0 to 1.0 at 10 fps should yield 11 frames (inclusive of end)
    frames = generate_frame_times(0.0, 1.0, fps=10)
    assert len(frames) == 11, f"Expected 11 frames, got {len(frames)}"
    assert frames[-1] == 1.0, f"Expected last frame to be 1.0, got {frames[-1]}"
EOF

cat > "$WORKSPACE_DIR/tests/test_renderer.py" << 'EOF'
import sys, os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from svg.renderer import render_svg

def test_render_svg_viewbox():
    # width 800, height 600
    res = render_svg(800, 600, [])
    assert 'viewBox="0 0 800 600"' in res, f"viewBox is incorrect in SVG: {res}"
EOF

# Ensure permissions
chown -R ga:ga "$WORKSPACE_DIR"

# Copy tests to hidden location to prevent agent from tampering with tests
sudo mkdir -p /var/lib/svg_tests
sudo cp -r "$WORKSPACE_DIR/tests/"* /var/lib/svg_tests/

# ─────────────────────────────────────────────────────────────
# 3. Environment Setup
# ─────────────────────────────────────────────────────────────

# Record start time
date +%s > /tmp/task_start_time.txt

# Start VS Code
su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Visual Studio Code"; then
        break
    fi
    sleep 1
done

# Maximize and Focus
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="