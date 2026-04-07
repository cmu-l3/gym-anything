#!/bin/bash
echo "=== Exporting spritesheet_game_export results ==="

# Configuration
FRAMES_DIR="/home/ga/OpenToonz/output/spritesheet_frames"
SPRITESHEET_PATH="/home/ga/OpenToonz/output/spritesheet.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_JSON="/tmp/task_result.json"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# Helper python script to analyze images
cat > /tmp/analyze_images.py << 'EOF'
import os
import sys
import json
import glob
from PIL import Image

frames_dir = sys.argv[1]
spritesheet_path = sys.argv[2]
task_start = float(sys.argv[3])

result = {
    "frames_count": 0,
    "frames_valid_res": 0,
    "frames_valid_alpha": 0,
    "frames_new": 0,
    "spritesheet_exists": False,
    "spritesheet_width": 0,
    "spritesheet_height": 0,
    "spritesheet_mode": "None",
    "spritesheet_new": False,
    "spritesheet_size_bytes": 0
}

# Analyze Frames
frame_files = glob.glob(os.path.join(frames_dir, "*.png"))
result["frames_count"] = len(frame_files)

if frame_files:
    valid_res_count = 0
    valid_alpha_count = 0
    new_count = 0
    
    # Check sample of frames (first 5 and last 5) to save time, or all if small count
    frames_to_check = frame_files if len(frame_files) < 20 else frame_files[:5] + frame_files[-5:]
    
    for f in frames_to_check:
        try:
            # Check timestamp
            if os.path.getmtime(f) > task_start:
                new_count += 1
                
            with Image.open(f) as img:
                if img.width == 256 and img.height == 256:
                    valid_res_count += 1
                if img.mode == 'RGBA' or (img.mode == 'P' and 'transparency' in img.info):
                    valid_alpha_count += 1
        except Exception as e:
            print(f"Error reading frame {f}: {e}")

    # Extrapolate if we sampled
    if len(frame_files) > len(frames_to_check):
        ratio = len(frame_files) / len(frames_to_check)
        result["frames_valid_res"] = int(valid_res_count * ratio)
        result["frames_valid_alpha"] = int(valid_alpha_count * ratio)
        result["frames_new"] = int(new_count * ratio)
    else:
        result["frames_valid_res"] = valid_res_count
        result["frames_valid_alpha"] = valid_alpha_count
        result["frames_new"] = new_count

# Analyze Spritesheet
if os.path.exists(spritesheet_path):
    result["spritesheet_exists"] = True
    result["spritesheet_size_bytes"] = os.path.getsize(spritesheet_path)
    
    if os.path.getmtime(spritesheet_path) > task_start:
        result["spritesheet_new"] = True
        
    try:
        with Image.open(spritesheet_path) as img:
            result["spritesheet_width"] = img.width
            result["spritesheet_height"] = img.height
            result["spritesheet_mode"] = img.mode
    except Exception as e:
        print(f"Error reading spritesheet: {e}")

print(json.dumps(result))
EOF

# Run analysis
echo "Running image analysis..."
python3 /tmp/analyze_images.py "$FRAMES_DIR" "$SPRITESHEET_PATH" "$TASK_START" > "$RESULT_JSON"

echo "Analysis complete. Result:"
cat "$RESULT_JSON"

# Clean up temp script
rm /tmp/analyze_images.py

echo "=== Export complete ==="