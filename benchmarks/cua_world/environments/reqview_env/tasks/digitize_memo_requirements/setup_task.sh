#!/bin/bash
set -e
echo "=== Setting up digitize_memo_requirements task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Prepare Project
# Kill any running ReqView
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project
PROJECT_PATH=$(setup_task_project "digitize_memo")
echo "Task project path: $PROJECT_PATH"

# 2. Generate the Memo Image
# We need python3 and Pillow to generate a clean text image.
# If Pillow isn't there, we install it.
if ! python3 -c "import PIL" 2>/dev/null; then
    echo "Installing Pillow for image generation..."
    pip3 install Pillow --quiet --break-system-packages 2>/dev/null || pip3 install Pillow --quiet
fi

echo "Generating memo image..."
python3 - << 'EOF'
from PIL import Image, ImageDraw, ImageFont
import os

# Create a white image
width, height = 800, 600
img = Image.new('RGB', (width, height), color='white')
d = ImageDraw.Draw(img)

# Try to load fonts, fallback to default if system fonts missing
try:
    # Common Linux locations
    font_header = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf", 28)
    font_text = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf", 18)
    font_label = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf", 16)
except:
    print("Warning: Custom fonts not found, using default")
    font_header = ImageFont.load_default()
    font_text = ImageFont.load_default()
    font_label = ImageFont.load_default()

# Draw Memo Header
d.text((50, 40), "MEMO: Audit Module Constraints", fill='black', font=font_header)
d.text((50, 80), "Date: 2024-03-15  |  From: Security Lead", fill='#555555', font=font_text)
d.line((50, 110, 750, 110), fill='black', width=2)

# Draw Requirements
reqs = [
    ("1. The system shall encrypt all audit logs using AES-256.", "[Priority: High]"),
    ("2. Audit logs must be retained for a minimum of 5 years.", "[Priority: Medium]"),
    ("3. The system shall notify the administrator of any integrity violations.", "[Priority: High]")
]

y_pos = 150
for text, priority in reqs:
    # Requirement Text
    d.text((50, y_pos), text, fill='black', font=font_text)
    
    # Priority Label (in red)
    d.text((50, y_pos + 25), priority, fill='red', font=font_label)
    
    y_pos += 80

# Footer
d.text((50, 550), "* Please enter these into the SRS immediately.", fill='blue', font=font_text)

# Save
img.save("/home/ga/Desktop/audit_memo.png")
EOF

# Ensure file permissions
chown ga:ga /home/ga/Desktop/audit_memo.png
chmod 644 /home/ga/Desktop/audit_memo.png

# 3. Launch Application
# Launch ReqView with the project
launch_reqview_with_project "$PROJECT_PATH"

sleep 5
dismiss_dialogs
maximize_window

# Record initial file timestamp for SRS
SRS_FILE="$PROJECT_PATH/documents/SRS.json"
if [ -f "$SRS_FILE" ]; then
    stat -c %Y "$SRS_FILE" > /tmp/initial_srs_mtime.txt
else
    echo "0" > /tmp/initial_srs_mtime.txt
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="