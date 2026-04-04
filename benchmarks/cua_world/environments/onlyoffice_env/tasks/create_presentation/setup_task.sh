#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Presentation Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Presentations"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a blank presentation
PRES_PATH="$WORKSPACE_DIR/company_overview.pptx"

cat > /tmp/create_pres.py << 'PYEOF'
#!/usr/bin/env python3
from pptx import Presentation
from pptx.util import Inches, Pt
import sys

prs = Presentation()

# Set slide size (standard 16:9)
prs.slide_width = Inches(10)
prs.slide_height = Inches(7.5)

# Slide 1: Title slide (already exists as default)
title_slide_layout = prs.slide_layouts[0]  # Title Slide layout
slide1 = prs.slides.add_slide(title_slide_layout)
title = slide1.shapes.title
subtitle = slide1.placeholders[1]

title.text = "Company Overview"
subtitle.text = "Annual Report 2024"

prs.save(sys.argv[1])
print(f"Presentation created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_pres.py
python3 /tmp/create_pres.py "$PRES_PATH"
chown ga:ga "$PRES_PATH"

echo "✅ Presentation created at: $PRES_PATH"

# Launch ONLYOFFICE with the presentation
echo "Launching ONLYOFFICE Presentation Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$PRES_PATH' > /tmp/onlyoffice_pres_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_pres_task.log || true
    # We would still not exit the task, as it might start later or be a temporary issue
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
    # We would still not exit the task, as it might start later or be a temporary issue
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Create Presentation Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. The first slide is a title slide (already created)"
echo "  2. Add a new slide (Ctrl+M or Insert > New Slide)"
echo "  3. Add title to the new slide: 'Key Achievements'"
echo "  4. Add bullet points in the content area:"
echo "     - Revenue Growth: 25%"
echo "     - New Customers: 500+"
echo "     - Product Launches: 3"
echo "  5. Save the presentation (Ctrl+S)"
