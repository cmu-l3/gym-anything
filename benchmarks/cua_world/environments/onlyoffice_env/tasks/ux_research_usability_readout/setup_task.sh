#!/bin/bash
echo "=== Setting up UX Research Usability Readout task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create necessary directories
WORKSPACE_DIR="/home/ga/Documents/Presentations"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# 1. Generate realistic CSV usability data (30 participants)
# Ground Truth calculations: 
# Total Tasks = 30 * 3 = 90. Successes = 74. Success Rate = 74/90 = 82.22%
# SUS Scores sum = 2055. Average = 2055 / 30 = 68.5
cat > /tmp/generate_ux_data.py << 'EOF'
import csv
import os

data = [
    ["Participant_ID", "Age", "Tech_Savvy", "Task1_Success", "Task2_Success", "Task3_Success", "Time_On_Task_Sec", "SUS_Score"],
    ["P01", 28, "High", 1, 1, 1, 145, 85],
    ["P02", 45, "Medium", 1, 1, 0, 210, 60],
    ["P03", 32, "High", 1, 1, 1, 130, 90],
    ["P04", 55, "Low", 0, 1, 0, 340, 45],
    ["P05", 22, "High", 1, 1, 1, 110, 95],
    ["P06", 38, "Medium", 1, 1, 1, 185, 70],
    ["P07", 41, "Medium", 1, 0, 1, 240, 55],
    ["P08", 29, "High", 1, 1, 1, 125, 87],
    ["P09", 62, "Low", 1, 1, 0, 315, 50],
    ["P10", 35, "High", 1, 1, 1, 150, 75],
    ["P11", 27, "Medium", 1, 1, 1, 160, 65],
    ["P12", 48, "Low", 0, 1, 1, 290, 55],
    ["P13", 31, "High", 1, 1, 1, 140, 80],
    ["P14", 39, "Medium", 1, 0, 1, 220, 60],
    ["P15", 24, "High", 1, 1, 1, 115, 92],
    ["P16", 51, "Medium", 1, 1, 1, 205, 67],
    ["P17", 33, "High", 1, 1, 1, 135, 82],
    ["P18", 44, "Low", 1, 0, 0, 300, 42],
    ["P19", 26, "High", 1, 1, 1, 120, 88],
    ["P20", 37, "Medium", 1, 1, 1, 175, 72],
    ["P21", 58, "Low", 0, 1, 0, 330, 48],
    ["P22", 30, "High", 1, 1, 1, 145, 78],
    ["P23", 42, "Medium", 1, 1, 1, 190, 65],
    ["P24", 25, "High", 1, 1, 1, 125, 85],
    ["P25", 49, "Medium", 1, 0, 1, 260, 58],
    ["P26", 34, "High", 1, 1, 1, 155, 75],
    ["P27", 60, "Low", 0, 1, 0, 350, 40],
    ["P28", 28, "Medium", 1, 1, 1, 165, 70],
    ["P29", 46, "Medium", 1, 1, 1, 215, 62],
    ["P30", 36, "High", 1, 1, 1, 140, 76]
]

filepath = "/home/ga/Documents/Presentations/usability_data.csv"
with open(filepath, "w", newline='') as f:
    writer = csv.writer(f)
    writer.writerows(data)

os.chown(filepath, 1000, 1000)  # Assuming ga is 1000:1000
EOF
python3 /tmp/generate_ux_data.py

# 2. Generate user quotes file
QUOTES_PATH="$WORKSPACE_DIR/user_quotes.txt"
cat > "$QUOTES_PATH" << 'EOF'
=== USER RESEARCH QUOTES - EXPRESS CHECKOUT ===

Participant 04: "I wasn't sure if my payment went through because the confirmation screen loaded too quickly."
Participant 05: "The new auto-fill feature for the address saved me so much time. It's incredibly smooth."
Participant 12: "I struggled to find where to enter my discount code. It was hidden behind a dropdown."
Participant 18: "Overall it's fine, but the text color on the 'Submit Order' button is a bit hard to read against that background."
Participant 25: "I love that I didn't have to create an account to finish the purchase. Guest checkout is a lifesaver."
EOF
chown ga:ga "$QUOTES_PATH"

# 3. Generate a dummy prototype screenshot using ImageMagick
IMAGE_PATH="$WORKSPACE_DIR/checkout_prototype.png"
if command -v convert &> /dev/null; then
    sudo -u ga convert -size 1280x720 xc:"#f8f9fa" \
        -fill "#ffffff" -draw "roundrectangle 340,100 940,620 20,20" \
        -fill "#000000" -pointsize 32 -font Helvetica-Bold -annotate +400+180 "Express Checkout" \
        -fill "#6c757d" -pointsize 20 -font Helvetica -annotate +400+230 "Shipping Information" \
        -fill "#e9ecef" -draw "roundrectangle 400,260 880,310 5,5" \
        -fill "#e9ecef" -draw "roundrectangle 400,340 880,390 5,5" \
        -fill "#0d6efd" -draw "roundrectangle 400,500 880,560 10,10" \
        -fill "#ffffff" -pointsize 24 -font Helvetica-Bold -annotate +560+540 "Submit Order" \
        "$IMAGE_PATH"
else
    # Fallback to copy an existing image or create empty
    sudo -u ga touch "$IMAGE_PATH"
fi

# Ensure ONLYOFFICE is completely closed before starting
pkill -f "onlyoffice-desktopeditors" > /dev/null 2>&1 || true
sleep 2

# Launch ONLYOFFICE Presentation Editor
if ! pgrep -f "onlyoffice-desktopeditors" > /dev/null; then
    echo "Starting ONLYOFFICE..."
    su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new:slide &"
    sleep 8
fi

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ONLYOFFICE"; then
        break
    fi
    sleep 1
done

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "ONLYOFFICE" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ONLYOFFICE" 2>/dev/null || true

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="