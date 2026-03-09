#!/bin/bash
set -e

echo "=== Setting up Blender 3D environment ==="

# Wait for desktop to be ready
sleep 5

# Create projects directory with proper ownership FIRST
PROJECTS_DIR="/home/ga/BlenderProjects"
DEMOS_DIR="/home/ga/BlenderDemos"
mkdir -p "$PROJECTS_DIR"
mkdir -p "$DEMOS_DIR"
chown -R ga:ga "$PROJECTS_DIR"
chown -R ga:ga "$DEMOS_DIR"

# Create Blender configuration directories
echo "Creating Blender config directories..."
mkdir -p /home/ga/.config/blender/4.2/config
mkdir -p /home/ga/.config/blender/4.2/scripts/addons
mkdir -p /home/ga/.config/blender/4.2/scripts/presets
mkdir -p /home/ga/.local/share/blender
mkdir -p /home/ga/.cache/blender
chown -R ga:ga /home/ga/.config/blender
chown -R ga:ga /home/ga/.local/share/blender
chown -R ga:ga /home/ga/.cache/blender

# Create temporary directory for Blender
mkdir -p /tmp/blender_temp
chmod 777 /tmp/blender_temp

# ================================================================
# DOWNLOAD OFFICIAL BLENDER DEMO FILES (REALISTIC DATA)
# ================================================================
echo "Downloading official Blender demo files..."
cd "$DEMOS_DIR"

# Download Blender 4.0 splash (small, good for testing)
SPLASH_URL="https://download.blender.org/demo/splash/blender-4.0-splash.blend"
SPLASH_FILE="blender-4.0-splash.blend"
if [ ! -f "$SPLASH_FILE" ]; then
    echo "Downloading official splash screen scene (33MB)..."
    wget -q --show-progress "$SPLASH_URL" -O "$SPLASH_FILE" 2>/dev/null || \
    curl -sL "$SPLASH_URL" -o "$SPLASH_FILE" || \
    echo "Warning: Could not download splash file"
fi

# Download classroom scene (classic Blender demo)
CLASSROOM_URL="https://download.blender.org/demo/test/classroom.zip"
CLASSROOM_ZIP="classroom.zip"
if [ ! -f "classroom/classroom.blend" ]; then
    echo "Downloading classroom demo scene (70MB)..."
    wget -q --show-progress "$CLASSROOM_URL" -O "$CLASSROOM_ZIP" 2>/dev/null || \
    curl -sL "$CLASSROOM_URL" -o "$CLASSROOM_ZIP" || \
    echo "Warning: Could not download classroom"

    if [ -f "$CLASSROOM_ZIP" ]; then
        unzip -q -o "$CLASSROOM_ZIP" 2>/dev/null || true
        rm -f "$CLASSROOM_ZIP"
    fi
fi

# Download BMW benchmark scene (smaller, good for render tests)
BMW_URL="https://download.blender.org/demo/test/BMW27.blend.zip"
BMW_ZIP="BMW27.blend.zip"
if [ ! -f "BMW27.blend" ]; then
    echo "Downloading BMW benchmark scene (3MB)..."
    wget -q --show-progress "$BMW_URL" -O "$BMW_ZIP" 2>/dev/null || \
    curl -sL "$BMW_URL" -o "$BMW_ZIP" || \
    echo "Warning: Could not download BMW scene"

    if [ -f "$BMW_ZIP" ]; then
        unzip -q -o "$BMW_ZIP" 2>/dev/null || true
        rm -f "$BMW_ZIP"
    fi
fi

# Set ownership of demo files
chown -R ga:ga "$DEMOS_DIR"

# List downloaded files
echo "Downloaded demo files:"
ls -la "$DEMOS_DIR"

# ================================================================
# COPY DEMO FILE TO PROJECTS (for task use)
# ================================================================
# Use BMW scene for render task (small, quick to render)
if [ -f "$DEMOS_DIR/BMW27.blend" ]; then
    cp "$DEMOS_DIR/BMW27.blend" "$PROJECTS_DIR/render_scene.blend"
    echo "Using BMW27.blend as render scene"
# Fallback to classroom if BMW not available
elif [ -d "$DEMOS_DIR/classroom" ]; then
    cp "$DEMOS_DIR/classroom/classroom.blend" "$PROJECTS_DIR/render_scene.blend" 2>/dev/null || true
    echo "Using classroom.blend as render scene"
# Fallback to splash
elif [ -f "$DEMOS_DIR/blender-4.0-splash.blend" ]; then
    cp "$DEMOS_DIR/blender-4.0-splash.blend" "$PROJECTS_DIR/render_scene.blend"
    echo "Using splash as render scene"
fi

# Set ownership
chown -R ga:ga "$PROJECTS_DIR"

# ================================================================
# CONFIGURE BLENDER GPU RENDERING
# ================================================================
echo "Configuring Blender GPU rendering preferences..."
cat > /tmp/configure_gpu.py << 'GPU_EOF'
import bpy
import sys

prefs = bpy.context.preferences
cycles_prefs = prefs.addons['cycles'].preferences

# Detect available compute devices
print("Detecting GPU compute devices...")

# Try GPU backends in order of preference
gpu_configured = False
for device_type in ['CUDA', 'OPTIX', 'HIP', 'ONEAPI', 'METAL']:
    try:
        cycles_prefs.compute_device_type = device_type
        cycles_prefs.get_devices()

        # Check if any devices are available
        devices = cycles_prefs.devices
        gpu_devices = [d for d in devices if d.type != 'CPU']

        if gpu_devices:
            print(f"Found {len(gpu_devices)} {device_type} device(s)")
            for device in devices:
                device.use = True
                print(f"  - {device.name}: enabled ({device.type})")
            gpu_configured = True
            break
    except Exception as e:
        print(f"  {device_type}: not available ({e})")
        continue

if not gpu_configured:
    # Fall back to CPU
    print("No GPU found, using CPU rendering")
    cycles_prefs.compute_device_type = 'NONE'
    for device in cycles_prefs.devices:
        if device.type == 'CPU':
            device.use = True
            print(f"  - {device.name}: enabled (CPU)")

# Save preferences
try:
    bpy.ops.wm.save_userpref()
    print("Blender preferences saved")
except:
    print("Could not save preferences (may need UI)")

# Print final configuration
print(f"\nFinal config: compute_device_type = {cycles_prefs.compute_device_type}")
GPU_EOF

# Run GPU configuration
su - ga -c "DISPLAY=:1 /opt/blender/blender --background --python /tmp/configure_gpu.py" 2>&1 | head -30 || echo "GPU config completed"

# ================================================================
# CREATE SIMPLE SCENE FOR ADD_SPHERE TASK (baseline scene)
# ================================================================
echo "Creating baseline scene for add_sphere task..."
cat > /tmp/create_baseline_scene.py << 'SCENE_EOF'
import bpy
import os

# Clear default scene
bpy.ops.wm.read_homefile(use_empty=True)

# Create a simple baseline scene with cube, camera, light
bpy.ops.mesh.primitive_cube_add(size=2, location=(0, 0, 1))
cube = bpy.context.active_object
cube.name = "BaseCube"

# Add material to cube
mat = bpy.data.materials.new(name="CubeMaterial")
mat.use_nodes = True
bsdf = mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.8, 0.2, 0.2, 1.0)
cube.data.materials.append(mat)

# Add camera
bpy.ops.object.camera_add(location=(7, -6, 5))
camera = bpy.context.active_object
camera.name = "MainCamera"

bpy.ops.object.constraint_add(type='TRACK_TO')
camera.constraints['Track To'].target = cube
camera.constraints['Track To'].track_axis = 'TRACK_NEGATIVE_Z'
camera.constraints['Track To'].up_axis = 'UP_Y'
bpy.context.scene.camera = camera

# Add sun light
bpy.ops.object.light_add(type='SUN', location=(5, 5, 10))
sun = bpy.context.active_object
sun.name = "SunLight"
sun.data.energy = 3.0

# Add plane for ground
bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, 0))
ground = bpy.context.active_object
ground.name = "Ground"

# Set render settings (low samples for quick renders)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.render.resolution_x = 1920
scene.render.resolution_y = 1080
scene.render.resolution_percentage = 50  # 50% for faster renders
scene.cycles.samples = 32  # Low samples for testing
scene.cycles.use_denoising = True

# Save the file
output_path = "/home/ga/BlenderProjects/baseline_scene.blend"
bpy.ops.wm.save_as_mainfile(filepath=output_path)
print(f"Baseline scene saved to: {output_path}")
SCENE_EOF

# Run Blender headlessly to create baseline scene
su - ga -c "DISPLAY=:1 /opt/blender/blender --background --python /tmp/create_baseline_scene.py" 2>/dev/null || echo "Baseline scene creation completed"

# Set ownership
chown -R ga:ga /home/ga/.config/blender
chown -R ga:ga /home/ga/.local/share/blender
chown -R ga:ga /home/ga/.cache/blender
chown -R ga:ga "$PROJECTS_DIR"

# ================================================================
# CREATE LAUNCHER AND UTILITY SCRIPTS
# ================================================================
cat > /home/ga/Desktop/launch_blender.sh << 'LAUNCHER_EOF'
#!/bin/bash
export DISPLAY=:1
export BLENDER_USER_CONFIG=/home/ga/.config/blender
/opt/blender/blender "$@" &
LAUNCHER_EOF
chmod +x /home/ga/Desktop/launch_blender.sh
chown ga:ga /home/ga/Desktop/launch_blender.sh

# Create utility script for checking Blender info
cat > /usr/local/bin/blender-info << 'INFO_EOF'
#!/bin/bash
echo "=== Blender Information ==="
/opt/blender/blender --version

echo ""
echo "=== GPU Detection ==="
/opt/blender/blender --background --python-expr "
import bpy
prefs = bpy.context.preferences.addons['cycles'].preferences
print('Compute device type:', prefs.compute_device_type)
print('Available devices:')
for device in prefs.devices:
    print(f'  - {device.name}: {\"enabled\" if device.use else \"disabled\"} ({device.type})')
" 2>/dev/null

echo ""
echo "=== Demo Files ==="
ls -la /home/ga/BlenderDemos/

echo ""
echo "=== Project Files ==="
ls -la /home/ga/BlenderProjects/
INFO_EOF
chmod +x /usr/local/bin/blender-info

# Create script to query Blender scene state (for verification)
cat > /usr/local/bin/blender-query-scene << 'QUERY_EOF'
#!/bin/bash
# Query Blender scene state for verification
# Usage: blender-query-scene /path/to/file.blend

BLEND_FILE="${1:-}"
if [ -z "$BLEND_FILE" ] || [ ! -f "$BLEND_FILE" ]; then
    echo '{"error": "File not found or not specified"}'
    exit 1
fi

/opt/blender/blender --background "$BLEND_FILE" --python-expr "
import bpy
import json

scene = bpy.context.scene
result = {
    'object_count': len(bpy.data.objects),
    'mesh_count': len([o for o in bpy.data.objects if o.type == 'MESH']),
    'camera_count': len([o for o in bpy.data.objects if o.type == 'CAMERA']),
    'light_count': len([o for o in bpy.data.objects if o.type == 'LIGHT']),
    'material_count': len(bpy.data.materials),
    'render_engine': scene.render.engine,
    'resolution': [scene.render.resolution_x, scene.render.resolution_y],
    'samples': getattr(scene.cycles, 'samples', 0) if scene.render.engine == 'CYCLES' else 0,
    'objects': [{'name': o.name, 'type': o.type, 'location': list(o.location)} for o in bpy.data.objects]
}
print('JSON:' + json.dumps(result))
" 2>/dev/null | grep '^JSON:' | cut -c6-
QUERY_EOF
chmod +x /usr/local/bin/blender-query-scene

# ================================================================
# LAUNCH BLENDER WITH RENDER SCENE
# ================================================================
echo "Launching Blender with render scene..."
if [ -f "$PROJECTS_DIR/render_scene.blend" ]; then
    su - ga -c "DISPLAY=:1 /opt/blender/blender $PROJECTS_DIR/render_scene.blend &"
elif [ -f "$PROJECTS_DIR/baseline_scene.blend" ]; then
    su - ga -c "DISPLAY=:1 /opt/blender/blender $PROJECTS_DIR/baseline_scene.blend &"
else
    su - ga -c "DISPLAY=:1 /opt/blender/blender &"
fi

# Wait for Blender to start
sleep 5

echo "=== Blender 3D setup complete ==="
echo "Demo files: $DEMOS_DIR"
echo "Project files: $PROJECTS_DIR"
ls -la "$PROJECTS_DIR"
