#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Repair 3D Asset Pipeline Task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

WORKSPACE_DIR="/home/ga/workspace/asset_pipeline"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data/test_models"

# ─────────────────────────────────────────────────────────────
# Create the buggy script
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/process_models.py" << 'EOF'
import os
import json
import glob

def process_obj(filepath):
    vertices = []
    uvs = []
    indices = []

    # Initialize bounding box
    min_bounds = [0.0, 0.0, 0.0]
    max_bounds = [0.0, 0.0, 0.0]

    has_valid_uvs = True

    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue

            # Parse line
            parts = line.split(' ')

            if parts[0] == 'v':
                vx, vy, vz = float(parts[1]), float(parts[2]), float(parts[3])
                vertices.append([vx, vy, vz])

                # Update bounds
                min_bounds[0] = min(min_bounds[0], vx)
                min_bounds[1] = min(min_bounds[1], vy)
                min_bounds[2] = min(min_bounds[2], vz)
                max_bounds[0] = max(max_bounds[0], vx)
                max_bounds[1] = max(max_bounds[1], vy)
                max_bounds[2] = max(max_bounds[2], vz)

            elif parts[0] == 'vt':
                u, v = float(parts[1]), float(parts[2])
                uvs.append([u, v])
                # Validate UVs
                if u < 0.0 or v < 0.0:
                    has_valid_uvs = False

            elif parts[0] == 'f':
                # Engine needs 0-based indices
                face_indices = []
                for p in parts[1:]:
                    if p:
                        v_idx = int(p.split('/')[0])
                        face_indices.append(v_idx)
                indices.append(face_indices)

    return {
        "name": os.path.basename(filepath),
        "vertex_count": len(vertices),
        "bounds": {"min": min_bounds, "max": max_bounds},
        "has_valid_uvs": has_valid_uvs,
        "indices": indices
    }

def main():
    input_dir = "data/test_models"
    output_file = "assets.json"

    obj_files = glob.glob(os.path.join(input_dir, "*.obj"))
    print(f"Found {len(obj_files)} models to process.")

    for obj_file in obj_files:
        model_data = process_obj(obj_file)
        
        # Write to manifest
        with open(output_file, 'w') as f:
            json.dump([model_data], f, indent=2)
            
    print(f"Successfully generated {output_file}")

if __name__ == "__main__":
    main()
EOF

# ─────────────────────────────────────────────────────────────
# Create visible test models
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/data/test_models/prop_barrel.obj" << 'EOF'
# Standard formatting
v -1.0 0.0 -1.0
v 1.0 0.0 -1.0
v 1.0 2.0 1.0
vt 0.0 0.0
vt 1.0 1.0
f 1/1/1 2/2/1 3/2/1
EOF

cat > "$WORKSPACE_DIR/data/test_models/env_cloud.obj" << 'EOF'
# Positive coordinate space
v 50.0 100.0 50.0
v 60.0 120.0 60.0
vt 0.5 0.5
f 1/1/1 2/1/1 1/1/1
EOF

cat > "$WORKSPACE_DIR/data/test_models/char_hero.obj" << 'EOF'
# Irregular spacing and bad UVs
v   -5.0    10.0  -5.0
v  5.0 10.0   5.0
vt 1.5 0.5
f 1/1/1 2/1/1 1/1/1
EOF

# ─────────────────────────────────────────────────────────────
# Create hidden evaluation models (Hidden from agent)
# ─────────────────────────────────────────────────────────────
HIDDEN_DIR="/var/lib/asset_pipeline/hidden_models"
mkdir -p "$HIDDEN_DIR"

cat > "$HIDDEN_DIR/hidden_skybox.obj" << 'EOF'
# Tests whitespace, positive offset, and UV > 1.0
v   100.0   200.0   300.0
v 150.0 250.0 350.0
vt 1.5 0.5
f 1/1/1 2/1/1 1/1/1
EOF

cat > "$HIDDEN_DIR/hidden_ground.obj" << 'EOF'
# Tests negative space bounds
v -10.0 -5.0 -10.0
v -5.0 -1.0 -5.0
vt 0.5 0.5
f 1/1/1 2/1/1 1/1/1
EOF

# Fix permissions
chown -R ga:ga "$WORKSPACE_DIR"
chmod 700 /var/lib/asset_pipeline

# ─────────────────────────────────────────────────────────────
# Set up VS Code environment
# ─────────────────────────────────────────────────────────────
# Launch VSCode
if ! pgrep -f "code" > /dev/null; then
    echo "Starting VS Code..."
    su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR/process_models.py &"
    sleep 5
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Visual Studio Code"; then
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true

# Dismiss dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="