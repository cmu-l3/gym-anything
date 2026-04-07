#!/bin/bash
echo "=== Setting up scientific_microscopy_dataset_extraction task ==="

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Create directories
mkdir -p /home/ga/Videos/lab_data
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Pictures

# =====================================================================
# Real Data Sourcing
# Download a real public video and process it to simulate a washed-out 
# brightfield microscopy time-lapse (grayscale, low contrast, 1080p)
# =====================================================================
echo "Downloading source video data..."
SOURCE_URL="http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4"
RAW_FILE="/tmp/raw_source.mp4"

# Download the file (with silent failover handling)
curl -sL -o "$RAW_FILE" "$SOURCE_URL" || wget -qO "$RAW_FILE" "$SOURCE_URL"

if [ ! -f "$RAW_FILE" ] || [ ! -s "$RAW_FILE" ]; then
    echo "Warning: Download failed, generating synthetic proxy video as fallback..."
    # Fallback only used if network fails: Generate a noisy cellular-looking proxy
    ffmpeg -y -f lavfi -i "cellauto=s=1920x1080:rate=30" -t 120 -c:v libx264 -preset ultrafast "$RAW_FILE" 2>/dev/null
fi

echo "Processing video to simulate raw microscopy data..."
# Take 120 seconds, make it grayscale, reduce contrast to 0.4 (washed out), scale to 1920x1080
ffmpeg -y -i "$RAW_FILE" \
    -vf "format=gray,eq=contrast=0.4:brightness=0.2,scale=1920:1080" \
    -t 120 -c:v libx264 -preset fast -b:v 4M -an \
    /home/ga/Videos/lab_data/microscopy_timelapse.mp4 2>/dev/null

rm -f "$RAW_FILE"

# Create the extraction protocol document
cat > /home/ga/Documents/extraction_protocol.txt << 'PROTOEOF'
PROTOCOL: ML Dataset Image Sequence Extraction
SAMPLE: 44B
DATE: 2026-03-10

1. TARGET EVENT: 
   The target mitosis event occurs exactly between 01:16 and 01:21 in the time-lapse.
   (Duration: 5 seconds).

2. SPATIAL BOUNDING BOX: 
   The dividing cell is located in the upper right quadrant. 
   Crop a 500x500 square region with its top-left corner located exactly at X=1350, Y=150.

3. VISUAL ENHANCEMENT: 
   The raw microscope feed is washed out. Apply a contrast enhancement factor of exactly 1.5 
   (increase contrast by 50%) during extraction to highlight the cell boundaries.

4. OUTPUT FORMAT: 
   Extract every frame of this 5-second window as a PNG image into a new directory 
   at `/home/ga/Pictures/dataset_44B/`. 
   Use a 3-digit sequential naming scheme (e.g., frame_001.png, frame_002.png).

5. DOCUMENTATION: 
   Create a metadata manifest at `/home/ga/Pictures/dataset_44B/manifest.json`.
   It must be valid JSON containing the following exact keys with their numeric values:
   - "start_time" (in seconds)
   - "duration" (in seconds)
   - "crop_x"
   - "crop_y"
   - "crop_width"
   - "crop_height"
   - "contrast_factor"
PROTOEOF

# Fix permissions
chown -R ga:ga /home/ga/Videos /home/ga/Documents /home/ga/Pictures

# Open terminal for the agent since this is primarily a CLI/FFmpeg task
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"
    sleep 3
fi

# Maximize the terminal window
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot for evidence
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="