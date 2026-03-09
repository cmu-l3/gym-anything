#!/bin/bash
set -e
echo "=== Setting up Fix Slide Layout Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create directory
mkdir -p /home/ga/Documents/Presentations

# Generate the "broken" ODP file using python/odfpy in the container
# This ensures we have a specifically broken state (overflow, overlap, bad alignment)
cat > /tmp/gen_messy_odp.py << 'EOF'
from odf.opendocument import OpenDocumentPresentation
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties, TextProperties, ParagraphProperties, GraphicProperties
from odf.text import P, Span
from odf.draw import Page, Frame, TextBox, Rect
import os

doc = OpenDocumentPresentation()

# --- Styles ---
# Title Style (Left Aligned - The Error)
s_title_left = Style(name="TitleLeft", family="paragraph")
s_title_left.addElement(ParagraphProperties(textalign="start"))
s_title_left.addElement(TextProperties(fontsize="44pt", fontfamily="Liberation Sans"))
doc.styles.addElement(s_title_left)

# Standard Text
s_standard = Style(name="Standard", family="paragraph")
s_standard.addElement(TextProperties(fontsize="18pt", fontfamily="Liberation Sans"))
doc.styles.addElement(s_standard)

# Tiny Text (The Error)
s_tiny = Style(name="TinyText", family="paragraph")
s_tiny.addElement(TextProperties(fontsize="8pt", fontfamily="Liberation Sans"))
doc.styles.addElement(s_tiny)

# --- Slide 1: Alignment Issue ---
page1 = Page(name="Slide 1")
doc.presentation.addElement(page1)

# Title Frame
fr1 = Frame(stylename="standard", width="25cm", height="3cm", x="1.4cm", y="1cm")
tb1 = TextBox()
p1 = P(stylename=s_title_left, text="Nebula Platform Launch")
tb1.addElement(p1)
fr1.addElement(tb1)
page1.addElement(fr1)

# Subtitle
fr1b = Frame(stylename="standard", width="25cm", height="3cm", x="1.4cm", y="5cm")
tb1b = TextBox()
tb1b.addElement(P(text="Q4 Strategy Meeting"))
fr1b.addElement(tb1b)
page1.addElement(fr1b)


# --- Slide 2: Overflow Issue ---
page2 = Page(name="Slide 2")
doc.presentation.addElement(page2)

# Title
fr2t = Frame(width="25cm", height="3cm", x="1.4cm", y="1cm")
tb2t = TextBox()
tb2t.addElement(P(text="New Features List"))
fr2t.addElement(tb2t)
page2.addElement(fr2t)

# Long List Frame (Standard layout, NO columns yet)
fr2 = Frame(width="25cm", height="15cm", x="1.4cm", y="4cm")
tb2 = TextBox()
features = [
    "Real-time Analytics", "Cloud Sync", "Multi-user Access", "Role-based Security",
    "API Gateway", "Data Export", "Custom Reporting", "Dashboard Widgets",
    "Mobile App Support", "Offline Mode", "Biometric Login", "Audit Logs",
    "Webhook Integrations", "SSO Support", "Dark Mode", "Localization",
    "Privacy Controls", "GDPR Compliance", "24/7 Support", "Knowledge Base"
]
for f in features:
    tb2.addElement(P(stylename=s_standard, text=f"• {f}"))
fr2.addElement(tb2)
page2.addElement(fr2)


# --- Slide 3: Overlap Issue ---
page3 = Page(name="Slide 3")
doc.presentation.addElement(page3)

# Title (Obscured)
fr3t = Frame(width="25cm", height="3cm", x="1.4cm", y="1cm")
tb3t = TextBox()
tb3t.addElement(P(text="Pricing Tiers"))
fr3t.addElement(tb3t)
page3.addElement(fr3t)

# Overlapping Shape (y=0.5cm puts it right over title)
fr3 = Frame(width="10cm", height="5cm", x="8cm", y="0.5cm")
rect = Rect()
fr3.addElement(rect)
tb3 = TextBox()
tb3.addElement(P(text="Enterprise Plan\n$999/mo"))
fr3.addElement(tb3)
page3.addElement(fr3)


# --- Slide 4: Font Size Issue ---
page4 = Page(name="Slide 4")
doc.presentation.addElement(page4)

# Title
fr4t = Frame(width="25cm", height="3cm", x="1.4cm", y="1cm")
tb4t = TextBox()
tb4t.addElement(P(text="Contact Us"))
fr4t.addElement(tb4t)
page4.addElement(fr4t)

# Tiny Text
fr4 = Frame(width="20cm", height="3cm", x="2cm", y="6cm")
tb4 = TextBox()
tb4.addElement(P(stylename=s_tiny, text="For inquiries: support@nebula.io"))
fr4.addElement(tb4)
page4.addElement(fr4)

doc.save("/home/ga/Documents/Presentations/product_launch_draft.odp")
print("Draft presentation created.")
EOF

# Run generator
echo "Generating presentation file..."
python3 /tmp/gen_messy_odp.py
chown ga:ga /home/ga/Documents/Presentations/product_launch_draft.odp

# Launch Impress
echo "Launching LibreOffice Impress..."
if ! pgrep -f "soffice.bin" > /dev/null; then
    su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/product_launch_draft.odp > /tmp/impress_startup.log 2>&1 &"
    
    # Wait for window using task_utils
    if ! wait_for_window "LibreOffice Impress" 45; then
        echo "WARNING: Impress window not detected within timeout"
    fi
fi

# Ensure window focus and maximization
echo "Configuring window..."
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Maximize using wmctrl
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="