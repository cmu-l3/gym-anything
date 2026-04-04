#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Debug Background Worker Task ==="

WORKSPACE_DIR="/home/ga/workspace/thumbnail_service"
ASSETS_DIR="/workspace/tasks/debug_background_worker/assets"

# Create workspace structure
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$WORKSPACE_DIR/test_images"
sudo -u ga mkdir -p "$WORKSPACE_DIR/output"
sudo -u ga mkdir -p "$WORKSPACE_DIR/.vscode"

# Install required Python packages
echo "Installing Python dependencies..."
pip3 install Pillow PyYAML --quiet 2>&1 || true

# Copy assets
echo "Copying task assets..."
if [ -d "$ASSETS_DIR" ]; then
    sudo -u ga cp "$ASSETS_DIR/worker.py" "$WORKSPACE_DIR/" 2>/dev/null || echo "worker.py will be created"
    sudo -u ga cp "$ASSETS_DIR/config.yaml" "$WORKSPACE_DIR/" 2>/dev/null || echo "config.yaml will be created"
    sudo -u ga cp "$ASSETS_DIR/queue.json" "$WORKSPACE_DIR/" 2>/dev/null || echo "queue.json will be created"
    sudo -u ga cp "$ASSETS_DIR/test_images/"* "$WORKSPACE_DIR/test_images/" 2>/dev/null || echo "test images will be downloaded"
fi

# Create worker.py if not exists
if [ ! -f "$WORKSPACE_DIR/worker.py" ]; then
    cat > "$WORKSPACE_DIR/worker.py" << 'WORKER_EOF'
#!/usr/bin/env python3
"""
Background worker for processing thumbnail generation jobs
"""
import json
import yaml
import os
import sys
from pathlib import Path
from PIL import Image

def load_config():
    """Load configuration from config.yaml"""
    config_path = Path(__file__).parent / "config.yaml"
    with open(config_path, 'r') as f:
        return yaml.safe_load(f)

def load_queue():
    """Load job queue from queue.json"""
    queue_path = Path(__file__).parent / "queue.json"
    with open(queue_path, 'r') as f:
        return json.load(f)

def save_queue(queue_data):
    """Save updated queue to queue.json"""
    queue_path = Path(__file__).parent / "queue.json"
    with open(queue_path, 'w') as f:
        json.dump(queue_data, f, indent=2)

def process_job(job, config):
    """Process a single thumbnail generation job"""
    job_id = job.get('id')
    image_path = job.get('image_path')
    
    print(f"Processing job {job_id}: {image_path}")
    
    # Validate configuration
    width = config.get('thumbnail_width', 0)
    height = config.get('thumbnail_height', 150)
    
    if width <= 0 or height <= 0:
        raise ValueError(f"Invalid dimensions: width={width}, height={height}")
    
    # Load source image
    workspace = Path(__file__).parent
    source_path = workspace / image_path
    
    if not source_path.exists():
        raise FileNotFoundError(f"Image not found: {source_path}")
    
    img = Image.open(source_path)
    
    # Generate thumbnail
    img.thumbnail((width, height), Image.Resampling.LANCZOS)
    
    # Save thumbnail
    output_dir = workspace / "output"
    output_dir.mkdir(exist_ok=True)
    
    output_filename = f"thumb_{job_id}_{source_path.name}"
    output_path = output_dir / output_filename
    
    img.save(output_path, quality=85)
    
    print(f"✓ Thumbnail saved: {output_path}")
    return output_filename

def main():
    """Main worker loop"""
    print("=== Thumbnail Worker Starting ===")
    
    try:
        # Load configuration
        config = load_config()
        print(f"Configuration loaded: thumbnail_width={config.get('thumbnail_width')}, thumbnail_height={config.get('thumbnail_height')}")
        
        # Load job queue
        queue_data = load_queue()
        jobs = queue_data if isinstance(queue_data, list) else queue_data.get('jobs', [])
        
        print(f"Found {len(jobs)} jobs in queue")
        
        # Process pending jobs
        processed_count = 0
        for job in jobs:
            if job.get('status') == 'pending':
                try:
                    output_file = process_job(job, config)
                    job['status'] = 'completed'
                    job['output'] = f"output/{output_file}"
                    processed_count += 1
                except Exception as e:
                    print(f"✗ Error processing job {job.get('id')}: {e}")
                    job['status'] = 'failed'
                    job['error'] = str(e)
        
        # Save updated queue
        save_queue(queue_data if isinstance(queue_data, list) else {'jobs': jobs})
        
        print(f"=== Worker Complete: {processed_count} jobs processed ===")
        
        return 0 if processed_count > 0 else 1
        
    except Exception as e:
        print(f"✗ Worker error: {e}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == "__main__":
    sys.exit(main())
WORKER_EOF
    chmod +x "$WORKSPACE_DIR/worker.py"
fi

# Create config.yaml with bug
if [ ! -f "$WORKSPACE_DIR/config.yaml" ]; then
    cat > "$WORKSPACE_DIR/config.yaml" << 'CONFIG_EOF'
# Thumbnail generation configuration
thumbnail_width: 0  # BUG: Must be positive integer
thumbnail_height: 150
output_format: JPEG
output_quality: 85
CONFIG_EOF
fi

# Create queue.json with sample jobs
if [ ! -f "$WORKSPACE_DIR/queue.json" ]; then
    cat > "$WORKSPACE_DIR/queue.json" << 'QUEUE_EOF'
[
  {
    "id": 1001,
    "image_path": "test_images/product1.jpg",
    "status": "pending",
    "created_at": "2024-01-15T10:30:00Z"
  },
  {
    "id": 1002,
    "image_path": "test_images/product2.jpg",
    "status": "pending",
    "created_at": "2024-01-15T10:31:00Z"
  }
]
QUEUE_EOF
fi

# Create or download test images
echo "Setting up test images..."
if [ ! -f "$WORKSPACE_DIR/test_images/product1.jpg" ]; then
    # Try to download a small test image
    cd "$WORKSPACE_DIR/test_images"
    wget -q -O product1.jpg "https://via.placeholder.com/400x300.jpg/09f/fff?text=Product+1" 2>/dev/null || {
        # Fallback: create with Python
        sudo -u ga python3 << 'IMAGE_EOF'
from PIL import Image, ImageDraw, ImageFont
import os

os.chdir('/home/ga/workspace/thumbnail_service/test_images')

for i, name in enumerate(['product1.jpg', 'product2.jpg'], 1):
    img = Image.new('RGB', (400, 300), color=(73 + i*20, 109 + i*10, 137 + i*5))
    draw = ImageDraw.Draw(img)
    draw.text((150, 140), f"Product {i}", fill=(255, 255, 255))
    img.save(name, 'JPEG')
    print(f"Created {name}")
IMAGE_EOF
    }
fi

if [ ! -f "$WORKSPACE_DIR/test_images/product2.jpg" ]; then
    cd "$WORKSPACE_DIR/test_images"
    wget -q -O product2.jpg "https://via.placeholder.com/400x300.jpg/f90/fff?text=Product+2" 2>/dev/null || {
        sudo -u ga python3 << 'IMAGE_EOF'
from PIL import Image, ImageDraw
import os

os.chdir('/home/ga/workspace/thumbnail_service/test_images')
if not os.path.exists('product2.jpg'):
    img = Image.new('RGB', (400, 300), color=(200, 100, 50))
    draw = ImageDraw.Draw(img)
    draw.text((150, 140), "Product 2", fill=(255, 255, 255))
    img.save('product2.jpg', 'JPEG')
    print("Created product2.jpg")
IMAGE_EOF
    }
fi

# Set permissions
sudo chown -R ga:ga "$WORKSPACE_DIR"
chmod -R u+rw "$WORKSPACE_DIR"

# Open VSCode with the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/worker.py'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Debug Background Worker Task Setup Complete ==="
echo "📝 Workspace: $WORKSPACE_DIR"
echo "📝 Instructions:"
echo "  1. Examine worker.py to understand the job processing"
echo "  2. Create .vscode/launch.json with Python debug config for worker.py"
echo "  3. Fix config.yaml: change thumbnail_width from 0 to positive (e.g., 200)"
echo "  4. Run worker to process jobs (python worker.py or via debugger)"
echo "  5. Verify job completion in queue.json and thumbnails in output/"