#!/bin/bash
set -e
echo "=== Setting up insert_revenue_chart task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure presentation directory exists
sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Create the initial 4-slide presentation using python-pptx
# We create it inside the container to ensure compatibility
cat > /tmp/create_qbr_presentation.py << 'PYEOF'
#!/usr/bin/env python3
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor

prs = Presentation()
prs.slide_width = Inches(13.333)
prs.slide_height = Inches(7.5)

# --- Slide 1: Title Slide ---
slide_layout = prs.slide_layouts[0]
slide1 = prs.slides.add_slide(slide_layout)
title1 = slide1.shapes.title
title1.text = "FY2024 Quarterly Business Review"
subtitle = slide1.placeholders[1]
subtitle.text = "Acme Technology Solutions — Prepared for Executive Leadership"

# --- Slide 2: Revenue Overview (target for chart) ---
slide_layout2 = prs.slide_layouts[1]
slide2 = prs.slides.add_slide(slide_layout2)
title2 = slide2.shapes.title
title2.text = "Revenue Overview"
body2 = slide2.placeholders[1]
tf2 = body2.text_frame
tf2.clear()
p = tf2.paragraphs[0]
p.text = "Our FY2024 revenue performance showed strong growth in the second half of the year, with Q4 representing our strongest quarter. Please refer to the chart below for detailed quarterly figures."
p.font.size = Pt(16)

# --- Slide 3: Key Achievements ---
slide_layout3 = prs.slide_layouts[1]
slide3 = prs.slides.add_slide(slide_layout3)
title3 = slide3.shapes.title
title3.text = "Key Achievements"
body3 = slide3.placeholders[1]
tf3 = body3.text_frame
tf3.text = "• Closed 47 new enterprise accounts\n• Achieved 118% of annual revenue target\n• Reduced customer churn rate to 5.1%"

# --- Slide 4: Q1 2025 Outlook ---
slide_layout4 = prs.slide_layouts[1]
slide4 = prs.slides.add_slide(slide_layout4)
title4 = slide4.shapes.title
title4.text = "Q1 2025 Outlook"
body4 = slide4.placeholders[1]
tf4 = body4.text_frame
tf4.text = "• Pipeline currently at $4.7M\n• Two enterprise deals in final negotiation\n• New product launch in March"

output_path = "/home/ga/Documents/Presentations/qbr_fy2024.pptx"
prs.save(output_path)
print(f"Created {output_path}")
PYEOF

# Run generation script
sudo -u ga python3 /tmp/create_qbr_presentation.py

# Verify creation
if [ ! -f "/home/ga/Documents/Presentations/qbr_fy2024.pptx" ]; then
    echo "ERROR: Failed to create presentation file"
    exit 1
fi

# Record initial file hash for anti-gaming
md5sum /home/ga/Documents/Presentations/qbr_fy2024.pptx | awk '{print $1}' > /tmp/initial_file_hash.txt

# Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/qbr_fy2024.pptx > /tmp/impress_startup.log 2>&1 &"

# Wait for window using util
if ! wait_for_window "impress\|qbr_fy2024" 30; then
    echo "WARNING: Impress window not detected within timeout"
fi

# Maximize window
WID=$(get_impress_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    # Dismiss any recovery dialogs if they appear (Esc key)
    sleep 1
    safe_xdotool ga :1 key Escape
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="