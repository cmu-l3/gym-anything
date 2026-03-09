#!/bin/bash
set -e
echo "=== Setting up Clean Up Screenshots Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Create a "fake" HR Portal page to screenshot
# This ensures the data is realistic (looks like a browser)
mkdir -p /tmp/site
cat > /tmp/site/index.html << HTML
<html>
<body style="margin:0; padding:0; background-color:#f0f2f5; font-family:sans-serif;">
    <div style="background-color:#0056b3; color:white; padding:20px;">
        <h1>HR Employee Portal</h1>
    </div>
    <div style="padding:40px; display:flex;">
        <div style="background:white; padding:20px; border-radius:8px; width:60%; box-shadow:0 2px 4px rgba(0,0,0,0.1);">
            <h2>Welcome, New Hire!</h2>
            <p>Please complete your onboarding tasks below:</p>
            <ul>
                <li>Tax Forms (W-4)</li>
                <li>Direct Deposit Setup</li>
                <li>Benefits Enrollment</li>
            </ul>
        </div>
        <div style="margin-left:20px; width:30%;">
            <div style="background:white; padding:20px; border-radius:8px; margin-bottom:20px;">
                <h3>Announcements</h3>
                <p>Open enrollment ends Friday!</p>
            </div>
        </div>
    </div>
</body>
</html>
HTML

# 2. Open Firefox and take a screenshot of the "Portal"
# This generates the "Raw Screenshot" asset
echo "Generating raw screenshot asset..."
su - ga -c "DISPLAY=:1 firefox /tmp/site/index.html &"
wait_for_window "Firefox" 20
sleep 5 # Wait for render

# Maximize to get full UI (address bar, etc)
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take the screenshot
mkdir -p /tmp/assets
DISPLAY=:1 scrot /tmp/assets/raw_screenshot.png

# Close Firefox
pkill -f firefox 2>/dev/null || true

# 3. Create the ODP file programmatically using this screenshot
echo "Generating ODP file..."
mkdir -p /home/ga/Documents/Presentations

python3 << 'PYEOF'
import os
from odf.opendocument import OpenDocumentPresentation
from odf.draw import Page, Frame, Image, TextBox
from odf.text import P
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties, TextProperties, GraphicProperties

# Path to the raw screenshot we just took
img_path = "/tmp/assets/raw_screenshot.png"

doc = OpenDocumentPresentation()

# Slide 1: Title
page1 = Page(name="Title")
doc.presentation.addElement(page1)
frame1 = Frame(width="25cm", height="3cm", x="1.5cm", y="5cm")
textbox1 = TextBox()
textbox1.addElement(P(text="New Employee Portal Guide"))
frame1.addElement(textbox1)
page1.addElement(frame1)

# Slide 2: The Screenshot (Target)
page2 = Page(name="Screenshot")
doc.presentation.addElement(page2)

# Title for Slide 2
frame2_title = Frame(width="25cm", height="2cm", x="1.5cm", y="1cm")
textbox2_title = TextBox()
textbox2_title.addElement(P(text="Login Screen Overview"))
frame2_title.addElement(textbox2_title)
page2.addElement(frame2_title)

# The Image Frame
# Add image file to document
if os.path.exists(img_path):
    img_ref = doc.addPicture(img_path)
    
    # Create a frame for the image
    # Place it centrally, somewhat large so it needs cropping
    photo_frame = Frame(width="24cm", height="13.5cm", x="2cm", y="4cm")
    img_element = Image(href=img_ref)
    photo_frame.addElement(img_element)
    page2.addElement(photo_frame)

# Slide 3: Next Steps
page3 = Page(name="NextSteps")
doc.presentation.addElement(page3)
frame3 = Frame(width="25cm", height="10cm", x="1.5cm", y="4cm")
textbox3 = TextBox()
textbox3.addElement(P(text="Next Steps:\n1. Log in\n2. Change Password"))
frame3.addElement(textbox3)
page3.addElement(frame3)

doc.save("/home/ga/Documents/Presentations/HR_Portal_Guide.odp")
print("ODP generated successfully.")
PYEOF

chown ga:ga /home/ga/Documents/Presentations/HR_Portal_Guide.odp

# 4. Launch Impress with the file
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/HR_Portal_Guide.odp > /tmp/impress.log 2>&1 &"

# Wait for load
wait_for_window "LibreOffice Impress" 30
sleep 5

# Maximize Impress
DISPLAY=:1 wmctrl -r "LibreOffice Impress" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Record start time
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_count.txt # Placeholder

# Initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="