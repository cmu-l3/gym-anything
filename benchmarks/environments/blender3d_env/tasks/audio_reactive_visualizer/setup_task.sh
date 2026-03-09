#!/bin/bash
echo "=== Setting up Audio Reactive Visualizer task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Directories
PROJECTS_DIR="/home/ga/BlenderProjects"
ASSETS_DIR="/home/ga/assets"
mkdir -p "$PROJECTS_DIR"
mkdir -p "$ASSETS_DIR"
chown -R ga:ga "$PROJECTS_DIR"
chown -R ga:ga "$ASSETS_DIR"

# Paths
START_BLEND="$PROJECTS_DIR/visualizer_start.blend"
AUDIO_FILE="$ASSETS_DIR/beat.wav"

# ================================================================
# 1. GENERATE AUDIO FILE (Synthetic but real WAV data)
# ================================================================
echo "Generating audio file at $AUDIO_FILE..."
python3 - << EOF
import wave
import math
import struct

sample_rate = 44100
duration = 4.0  # seconds
frequency = 100.0  # Hz (Bass)

with wave.open('$AUDIO_FILE', 'w') as w:
    w.setnchannels(1)      # Mono
    w.setsampwidth(2)      # 16-bit
    w.setframerate(sample_rate)
    
    total_frames = int(sample_rate * duration)
    data = []
    
    for i in range(total_frames):
        t = i / sample_rate
        # Create a beat pattern: 4 beats per second (120 BPM roughly)
        # Envelope: Decay every 0.5 seconds
        local_t = t % 0.5
        envelope = max(0, 1.0 - (local_t * 4.0)) # Linear decay
        
        # Sine wave
        value = int(32767.0 * envelope * math.sin(2 * math.pi * frequency * t))
        data.append(struct.pack('<h', value))
        
    w.writeframes(b''.join(data))
print("Audio file generated successfully.")
EOF

# ================================================================
# 2. CREATE STARTING BLEND FILE
# ================================================================
echo "Creating starting Blend file..."
cat > /tmp/create_start_scene.py << 'PYEOF'
import bpy
import os

# Reset
bpy.ops.wm.read_homefile(use_empty=True)

# Create SpeakerCone (Cylinder)
bpy.ops.mesh.primitive_cylinder_add(
    radius=1, 
    depth=2, 
    location=(0, 0, 1)
)
obj = bpy.context.active_object
obj.name = "SpeakerCone"

# Move origin to bottom so it scales up from ground
bpy.ops.object.origin_set(type='ORIGIN_CURSOR', center='MEDIAN')

# Add a ground plane
bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, 0))
ground = bpy.context.active_object
ground.name = "Ground"

# Add Camera
bpy.ops.object.camera_add(location=(8, -8, 6), rotation=(1.1, 0, 0.78))
cam = bpy.context.active_object
bpy.context.scene.camera = cam

# Add Light
bpy.ops.object.light_add(type='POINT', location=(4, -4, 5))

# Save
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/visualizer_start.blend")
PYEOF

su - ga -c "/opt/blender/blender --background --python /tmp/create_start_scene.py"

# ================================================================
# 3. LAUNCH BLENDER
# ================================================================
# Record start time
date +%s > /tmp/task_start_time.txt

echo "Launching Blender..."
pkill -f blender 2>/dev/null || true
su - ga -c "DISPLAY=:1 /opt/blender/blender '$START_BLEND' &"

# Wait for window
echo "Waiting for Blender to start..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "blender"; then
        echo "Blender started."
        break
    fi
    sleep 1
done

# Maximize
focus_blender
maximize_blender

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="