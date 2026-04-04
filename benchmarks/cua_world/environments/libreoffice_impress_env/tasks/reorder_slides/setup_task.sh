#!/bin/bash
set -e
echo "=== Setting up Reorder Slides Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming (file modification check)
date +%s > /tmp/task_start_time.txt

# Ensure directory exists
PRES_DIR="/home/ga/Documents/Presentations"
sudo -u ga mkdir -p "$PRES_DIR"

# Generate the SCRAMBLED presentation using python-pptx
# We run this as user 'ga' so permissions are correct
sudo -u ga python3 - << 'EOF'
from pptx import Presentation
from pptx.util import Pt

prs = Presentation()

# Define slides content
# The target correct order is:
# 0: Introduction
# 1: Hazards
# 2: Kit
# 3: Plan
# 4: Resources
# 5: Thank You

slides_content = [
    {
        "title": "Introduction to Emergency Preparedness",
        "bullets": [
            "Disasters can strike at any time",
            "Preparedness reduces fear and anxiety",
            "Know what to do before an emergency happens"
        ]
    },
    {
        "title": "Understanding Common Hazards",
        "bullets": [
            "Natural: Floods, hurricanes, wildfires",
            "Technological: Power outages, chemical spills",
            "Check local risk assessments"
        ]
    },
    {
        "title": "Building Your Emergency Kit",
        "bullets": [
            "Water: 1 gallon per person per day",
            "Food: 3-day supply of non-perishables",
            "Flashlight, radio, and first aid kit"
        ]
    },
    {
        "title": "Creating a Family Communication Plan",
        "bullets": [
            "Identify an out-of-town contact",
            "Pick meeting places (near home and outside neighborhood)",
            "Practice the plan twice a year"
        ]
    },
    {
        "title": "Resources and Support",
        "bullets": [
            "Visit Ready.gov for checklists",
            "Contact local emergency management",
            "Sign up for community alerts"
        ]
    },
    {
        "title": "Thank You & Contact Information",
        "bullets": [
            "Questions?",
            "Email: community.manager@example.org",
            "Stay safe and prepared!"
        ]
    }
]

# Scrambled order indices:
# 1. Resources (4)
# 2. Kit (2)
# 3. Intro (0)
# 4. Thank You (5)
# 5. Plan (3)
# 6. Hazards (1)
scrambled_indices = [4, 2, 0, 5, 3, 1]

for idx in scrambled_indices:
    content = slides_content[idx]
    # Use bullet layout (usually index 1)
    slide_layout = prs.slide_layouts[1]
    slide = prs.slides.add_slide(slide_layout)
    
    # Set title
    if slide.shapes.title:
        slide.shapes.title.text = content["title"]
    
    # Set bullets
    if slide.placeholders[1]:
        tf = slide.placeholders[1].text_frame
        tf.text = content["bullets"][0]
        for bullet in content["bullets"][1:]:
            p = tf.add_paragraph()
            p.text = bullet

save_path = "/home/ga/Documents/Presentations/emergency_preparedness.pptx"
prs.save(save_path)
print(f"Created presentation at {save_path}")
EOF

FILE_PATH="$PRES_DIR/emergency_preparedness.pptx"

# Ensure no other office instances are running
pkill -f soffice 2>/dev/null || true
sleep 1

# Launch LibreOffice Impress with the file
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress '$FILE_PATH' > /tmp/impress_task.log 2>&1 &"

# Wait for process
wait_for_process "soffice" 20

# Wait for window
if wait_for_window "LibreOffice Impress" 60; then
    echo "Impress window detected."
else
    # Fallback check for filename in title
    wait_for_window "emergency_preparedness" 10
fi

# Get window ID and maximize
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    echo "Maximizing window $wid"
    focus_window "$wid"
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    
    # Focus again to be sure
    focus_window "$wid"
    
    # Dismiss any recovery/tip dialogs if they appear (Esc key)
    sleep 2
    safe_xdotool ga :1 key Escape 2>/dev/null || true
else
    echo "WARNING: Could not find Impress window ID"
fi

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="