#!/bin/bash
set -e
echo "=== Setting up SWOT Analysis Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure Presentation directory exists
sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Create initial 2-slide presentation using Python
# We create an ODP file with specific content to simulate a work-in-progress
cat > /tmp/create_initial_pres.py << 'PYEOF'
import sys
# We will use simple XML generation if odfpy isn't fully robust for this, 
# but assuming odfpy is installed as per env spec.
try:
    from odf.opendocument import OpenDocumentPresentation
    from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties, TextProperties, GraphicProperties
    from odf.text import P
    from odf.draw import Page, Frame, TextBox, Image
    
    doc = OpenDocumentPresentation()

    # Slide 1: Title
    page1 = Page(name="Title")
    doc.presentation.addElement(page1)
    
    # Title Frame
    frame1 = Frame(width="25cm", height="3cm", x="1.5cm", y="8cm")
    textbox1 = TextBox()
    textbox1.addElement(P(text="Renewable Energy Transition Strategy"))
    frame1.addElement(textbox1)
    page1.addElement(frame1)

    # Subtitle Frame
    frame2 = Frame(width="25cm", height="2cm", x="1.5cm", y="12cm")
    textbox2 = TextBox()
    textbox2.addElement(P(text="Board Presentation - Q4 2024"))
    frame2.addElement(textbox2)
    page1.addElement(frame2)

    # Slide 2: Content
    page2 = Page(name="Background")
    doc.presentation.addElement(page2)
    
    # Title
    frame3 = Frame(width="25cm", height="2cm", x="1.5cm", y="1.5cm")
    textbox3 = TextBox()
    textbox3.addElement(P(text="Current Energy Profile"))
    frame3.addElement(textbox3)
    page2.addElement(frame3)

    # Bullets
    frame4 = Frame(width="25cm", height="12cm", x="1.5cm", y="4cm")
    textbox4 = TextBox()
    textbox4.addElement(P(text="• Annual energy consumption: 12,500 MWh"))
    textbox4.addElement(P(text="• Current renewable energy share: 15%"))
    textbox4.addElement(P(text="• Carbon emissions: 8,200 tonnes CO2e per year"))
    textbox4.addElement(P(text="• Energy cost trend: +8% year-over-year increase"))
    textbox4.addElement(P(text="• Target: 60% renewable by 2028"))
    frame4.addElement(textbox4)
    page2.addElement(frame4)

    doc.save("/home/ga/Documents/Presentations/renewable_energy_strategy.odp")
    print("Presentation created successfully.")

except Exception as e:
    print(f"Error creating presentation: {e}")
    sys.exit(1)
PYEOF

# Generate the file
python3 /tmp/create_initial_pres.py
sudo chown ga:ga /home/ga/Documents/Presentations/renewable_energy_strategy.odp

# Record initial file state
stat -c %Y /home/ga/Documents/Presentations/renewable_energy_strategy.odp > /tmp/initial_file_mtime.txt

# Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
if ! pgrep -f "soffice.bin" > /dev/null; then
    su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/renewable_energy_strategy.odp > /tmp/impress.log 2>&1 &"
fi

# Wait for window
wait_for_window "LibreOffice Impress" 60

# Maximize and Focus
WID=$(get_impress_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    safe_xdotool ga :1 key F11  # Fullscreen/Maximize often helps
    sleep 1
    # Ensure not in slideshow mode if F11 triggered it, though usually F5 is slideshow
    # Let's use wmctrl for maximizing to be safe
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any recovery dialogs if they appear (Simulate Esc)
safe_xdotool ga :1 key Escape
sleep 0.5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="