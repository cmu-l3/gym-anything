#!/bin/bash
echo "=== Setting up animate_ghibli_scene task ==="

# Create task directories
TASK_DIR="/home/ga/OpenToonz/task"
su - ga -c "mkdir -p $TASK_DIR"
su - ga -c "mkdir -p $TASK_DIR/agent_output"
su - ga -c "mkdir -p $TASK_DIR/layers"
su - ga -c "mkdir -p $TASK_DIR/reference_frames"

# Download Ghibli image from official source
# Using Spirited Away train scene - serene water scene perfect for animation
GHIBLI_IMAGE="$TASK_DIR/ghibli_scene.jpg"
echo "Downloading Ghibli artwork from official source..."

# Try multiple Ghibli images (in case one fails)
GHIBLI_URLS=(
    "https://www.ghibli.jp/gallery/chihiro050.jpg"
    "https://www.ghibli.jp/gallery/chihiro008.jpg"
    "https://www.ghibli.jp/gallery/ponyo050.jpg"
)

DOWNLOAD_SUCCESS=false
for url in "${GHIBLI_URLS[@]}"; do
    if wget -q --timeout=30 "$url" -O "$GHIBLI_IMAGE" 2>/dev/null; then
        if [ -s "$GHIBLI_IMAGE" ]; then
            echo "Successfully downloaded from: $url"
            DOWNLOAD_SUCCESS=true
            break
        fi
    fi
done

# Fallback: Use a sample image from OpenToonz samples if Ghibli download fails
if [ "$DOWNLOAD_SUCCESS" = false ]; then
    echo "Warning: Could not download Ghibli image, using sample scene"
    if [ -f "/home/ga/OpenToonz/samples/dwanko_run.tnz" ]; then
        # Extract first frame from sample animation
        cp /home/ga/OpenToonz/samples/dwanko_run.tnz "$TASK_DIR/sample_scene.tnz" || true
    fi
    # Create a placeholder image
    convert -size 1920x1080 xc:skyblue \
        -fill white -draw "circle 960,200 960,100" \
        -fill '#87CEEB' -draw "rectangle 0,600 1920,1080" \
        -fill '#4682B4' -draw "polygon 0,650 1920,700 1920,1080 0,1080" \
        "$GHIBLI_IMAGE" 2>/dev/null || \
    python3 -c "
from PIL import Image, ImageDraw
import random
img = Image.new('RGB', (1920, 1080), (135, 206, 235))
draw = ImageDraw.Draw(img)
# Sky gradient
for y in range(540):
    r = int(135 + (y/540) * 50)
    g = int(206 - (y/540) * 30)
    b = int(235 - (y/540) * 20)
    draw.line([(0, y), (1920, y)], fill=(r, g, b))
# Water
for y in range(540, 1080):
    r = int(70 + (y-540)/540 * 30)
    g = int(130 + (y-540)/540 * 30)
    b = int(180 - (y-540)/540 * 20)
    draw.line([(0, y), (1920, y)], fill=(r, g, b))
# Sun
draw.ellipse([860, 50, 1060, 250], fill=(255, 255, 200))
img.save('$GHIBLI_IMAGE')
"
fi

chown ga:ga "$GHIBLI_IMAGE"

# Generate layers using Python (depth-based separation)
echo "Generating animation layers..."
python3 << 'LAYER_SCRIPT'
import os
from PIL import Image
import numpy as np

TASK_DIR = "/home/ga/OpenToonz/task"
GHIBLI_IMAGE = f"{TASK_DIR}/ghibli_scene.jpg"
LAYERS_DIR = f"{TASK_DIR}/layers"

try:
    img = Image.open(GHIBLI_IMAGE).convert('RGB')
    img_array = np.array(img)

    height, width = img_array.shape[:2]

    # Simple depth estimation based on vertical position
    # Top = far (background), Bottom = near (foreground)
    depth_map = np.zeros((height, width), dtype=np.float32)
    for y in range(height):
        depth_map[y, :] = y / height

    # Additional depth cue: brightness (brighter = further in atmospheric perspective)
    gray = np.mean(img_array, axis=2) / 255.0
    depth_map = 0.7 * depth_map + 0.3 * (1 - gray)

    # Create 3 layers: background, midground, foreground
    layers = []
    thresholds = [0.33, 0.66, 1.0]
    layer_names = ['background', 'midground', 'foreground']

    for i, (name, thresh) in enumerate(zip(layer_names, thresholds)):
        if i == 0:
            mask = depth_map < thresholds[0]
        elif i == len(layer_names) - 1:
            mask = depth_map >= thresholds[-2]
        else:
            mask = (depth_map >= thresholds[i-1]) & (depth_map < thresholds[i])

        # Create RGBA layer
        layer_rgba = np.zeros((height, width, 4), dtype=np.uint8)
        layer_rgba[:, :, :3] = img_array
        layer_rgba[:, :, 3] = (mask * 255).astype(np.uint8)

        layer_img = Image.fromarray(layer_rgba, 'RGBA')
        layer_path = f"{LAYERS_DIR}/layer_{name}.png"
        layer_img.save(layer_path)
        print(f"Created layer: {layer_path}")
        layers.append({'name': name, 'path': layer_path, 'depth': i})

    # Save combined image as well
    img.save(f"{LAYERS_DIR}/combined.png")

    # Save layer info for verifier
    import json
    with open(f"{TASK_DIR}/layer_info.json", 'w') as f:
        json.dump({'layers': layers, 'width': width, 'height': height}, f, indent=2)

    print("Layer generation complete!")

except Exception as e:
    print(f"Layer generation error: {e}")
    # Create single layer fallback
    import shutil
    shutil.copy(GHIBLI_IMAGE, f"{LAYERS_DIR}/layer_main.png")
LAYER_SCRIPT

chown -R ga:ga "$TASK_DIR/layers"

# Create reference animation with particles and camera movement
echo "Creating reference animation project..."
python3 << 'REFERENCE_SCRIPT'
import os
import json
import subprocess
from PIL import Image, ImageDraw
import numpy as np
import random

TASK_DIR = "/home/ga/OpenToonz/task"
FRAME_COUNT = 60
FPS = 30

# Create reference frames with animation effects
REFERENCE_FRAMES_DIR = f"{TASK_DIR}/reference_frames"
os.makedirs(REFERENCE_FRAMES_DIR, exist_ok=True)

try:
    # Load base image
    base_img = Image.open(f"{TASK_DIR}/ghibli_scene.jpg").convert('RGBA')
    width, height = base_img.size

    # Animation parameters
    camera_offset = 0
    camera_speed = 2  # pixels per frame

    # Particle system (sparkles on water)
    particles = []
    for _ in range(20):
        particles.append({
            'x': random.randint(0, width),
            'y': random.randint(height//2, height),
            'vx': random.uniform(-1, 1),
            'vy': random.uniform(-2, 0),
            'size': random.randint(2, 6),
            'life': random.randint(20, 60),
            'brightness': random.randint(200, 255)
        })

    for frame_num in range(FRAME_COUNT):
        # Create frame
        frame = base_img.copy()
        draw = ImageDraw.Draw(frame, 'RGBA')

        # Apply subtle camera pan (crop and resize)
        crop_offset = int(camera_offset)
        if crop_offset > 0 and crop_offset < width // 10:
            cropped = frame.crop((crop_offset, 0, width, height))
            frame = cropped.resize((width, height), Image.LANCZOS)

        camera_offset += camera_speed * 0.1

        # Draw and update particles
        for p in particles:
            if p['life'] > 0:
                # Draw sparkle
                alpha = int(min(255, p['brightness'] * (p['life'] / 60)))
                draw.ellipse(
                    [p['x'] - p['size'], p['y'] - p['size'],
                     p['x'] + p['size'], p['y'] + p['size']],
                    fill=(255, 255, 255, alpha)
                )

                # Update particle
                p['x'] += p['vx']
                p['y'] += p['vy']
                p['life'] -= 1

                # Respawn
                if p['life'] <= 0 or p['y'] < height // 2:
                    p['x'] = random.randint(0, width)
                    p['y'] = random.randint(height * 2 // 3, height)
                    p['life'] = random.randint(20, 60)

        # Apply subtle wave distortion to bottom half (water)
        wave_amplitude = 2
        wave_frequency = 0.05
        phase = frame_num * 0.1

        frame_array = np.array(frame)
        for y in range(height * 2 // 3, height):
            offset = int(wave_amplitude * np.sin(wave_frequency * y + phase))
            if offset != 0:
                frame_array[y] = np.roll(frame_array[y], offset, axis=0)

        frame = Image.fromarray(frame_array)

        # Save frame
        frame_path = f"{REFERENCE_FRAMES_DIR}/frame_{frame_num:04d}.png"
        frame.convert('RGB').save(frame_path)

    print(f"Created {FRAME_COUNT} reference frames")

    # Create video from frames using ffmpeg
    video_path = f"{TASK_DIR}/reference_animation.mp4"
    subprocess.run([
        'ffmpeg', '-y', '-framerate', str(FPS),
        '-i', f'{REFERENCE_FRAMES_DIR}/frame_%04d.png',
        '-c:v', 'libx264', '-pix_fmt', 'yuv420p',
        '-preset', 'fast', '-crf', '23',
        video_path
    ], capture_output=True, timeout=120)

    if os.path.exists(video_path):
        print(f"Reference video created: {video_path}")
    else:
        print("Warning: Video creation may have failed")

    # Save animation parameters for verification
    animation_info = {
        'frame_count': FRAME_COUNT,
        'fps': FPS,
        'particles': {
            'count': 20,
            'type': 'sparkles',
            'region': 'water'
        },
        'camera': {
            'type': 'pan',
            'direction': 'right',
            'speed': camera_speed
        },
        'wave': {
            'amplitude': wave_amplitude,
            'frequency': wave_frequency
        }
    }

    with open(f"{TASK_DIR}/animation_info.json", 'w') as f:
        json.dump(animation_info, f, indent=2)

except Exception as e:
    print(f"Reference creation error: {e}")
    import traceback
    traceback.print_exc()
REFERENCE_SCRIPT

chown -R ga:ga "$TASK_DIR"

# Create clean OpenToonz project (no animation)
echo "Creating clean OpenToonz project for agent..."
python3 << 'CLEAN_PROJECT_SCRIPT'
import os
import xml.etree.ElementTree as ET

TASK_DIR = "/home/ga/OpenToonz/task"

# Create a simple TNZ project file structure
# OpenToonz TNZ files are actually XML

def create_clean_project():
    root = ET.Element('tnz')
    root.set('version', '71')

    # Scene properties
    scene = ET.SubElement(root, 'properties')
    ET.SubElement(scene, 'cameraSize').set('val', '1920 1080')
    ET.SubElement(scene, 'frameCount').set('val', '60')
    ET.SubElement(scene, 'fps').set('val', '30')

    # Levels - the image layers
    levels = ET.SubElement(root, 'levels')

    layer_files = ['layer_background.png', 'layer_midground.png', 'layer_foreground.png']
    for i, layer_file in enumerate(layer_files):
        layer_path = f"/home/ga/OpenToonz/task/layers/{layer_file}"
        if os.path.exists(layer_path):
            level = ET.SubElement(levels, 'level')
            level.set('name', layer_file.replace('.png', ''))
            level.set('path', layer_path)
            level.set('type', 'raster')

    # If no layers, use the main image
    if len(list(levels)) == 0:
        main_image = f"{TASK_DIR}/ghibli_scene.jpg"
        if os.path.exists(main_image):
            level = ET.SubElement(levels, 'level')
            level.set('name', 'main')
            level.set('path', main_image)
            level.set('type', 'raster')

    # Xsheet (timeline) - static, just showing the images
    xsheet = ET.SubElement(root, 'xsheet')
    for i, level in enumerate(levels.findall('level')):
        column = ET.SubElement(xsheet, 'column')
        column.set('index', str(i))
        column.set('level', level.get('name'))
        # All 60 frames show the same image (no animation yet)
        for frame in range(60):
            cell = ET.SubElement(column, 'cell')
            cell.set('frame', str(frame))
            cell.set('levelFrame', '0')

    # NO particles, NO camera movement, NO FX - agent must add these

    # Write project file
    tree = ET.ElementTree(root)
    project_path = f"{TASK_DIR}/clean_project.tnz"
    tree.write(project_path, encoding='utf-8', xml_declaration=True)

    print(f"Clean project created: {project_path}")
    return project_path

create_clean_project()
CLEAN_PROJECT_SCRIPT

chown -R ga:ga "$TASK_DIR"

# Record initial state
echo "0" > /tmp/initial_output_count
find "$TASK_DIR/agent_output" -type f \( -name "*.mp4" -o -name "*.png" -o -name "*.gif" \) 2>/dev/null | wc -l > /tmp/initial_output_count

# Verify all required files exist
IMAGE_PATH="$TASK_DIR/ghibli_scene.jpg"
REF_VIDEO="$TASK_DIR/reference_animation.mp4"

echo "Verifying task files..."

# Check Ghibli image
if [ -f "$IMAGE_PATH" ]; then
    SIZE=$(du -h "$IMAGE_PATH" | cut -f1)
    echo "  Ghibli image: $IMAGE_PATH ($SIZE)"
else
    echo "  WARNING: Ghibli image not found!"
fi

# Check reference video
if [ -f "$REF_VIDEO" ]; then
    SIZE=$(du -h "$REF_VIDEO" | cut -f1)
    echo "  Reference video: $REF_VIDEO ($SIZE)"
else
    echo "  WARNING: Reference video not found!"
fi

# Check output directory
if [ -d "$TASK_DIR/agent_output" ]; then
    echo "  Output directory: $TASK_DIR/agent_output (ready)"
else
    echo "  WARNING: Output directory not found!"
fi

# Focus and maximize OpenToonz window
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss any dialogs
for i in $(seq 1 3); do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.3
done

# Final dialog dismissal
for i in $(seq 1 3); do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.3
done

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Take final screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

# Final check
FINAL_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "opentoonz" | head -1)
echo "Final window title: $FINAL_TITLE"

echo "=== Task setup complete ==="
echo "  Ghibli scene: $GHIBLI_IMAGE"
echo "  Reference video: $TASK_DIR/reference_animation.mp4"
echo "  Clean project: $TASK_DIR/clean_project.tnz"
echo "  Agent should output to: $TASK_DIR/agent_output/"
