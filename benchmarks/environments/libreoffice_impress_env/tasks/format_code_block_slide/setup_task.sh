#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Format Code Block Slide Task ==="

# 1. Create Directories
sudo -u ga mkdir -p /home/ga/Documents/Presentations
sudo -u ga mkdir -p /home/ga/Desktop

# 2. Create the initial presentation (2 slides)
# Using python/odfpy to create a clean starting state
echo "Creating initial presentation..."
cat << 'PYEOF' | python3
from odf.opendocument import OpenDocumentPresentation
from odf.draw import Page, Frame, TextBox
from odf.text import P
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties

doc = OpenDocumentPresentation()

# Slide 1
page1 = Page(name="Slide1")
doc.presentation.addElement(page1)
frame1 = Frame(width="25cm", height="3cm", x="1.5cm", y="1cm")
page1.addElement(frame1)
tb1 = TextBox()
frame1.addElement(tb1)
tb1.addElement(P(text="User API V2 Overview"))

# Slide 2
page2 = Page(name="Slide2")
doc.presentation.addElement(page2)
frame2 = Frame(width="25cm", height="3cm", x="1.5cm", y="1cm")
page2.addElement(frame2)
tb2 = TextBox()
frame2.addElement(tb2)
tb2.addElement(P(text="Authentication Flow"))

doc.save("/home/ga/Documents/Presentations/api_docs_v2.odp")
PYEOF

sudo chown ga:ga /home/ga/Documents/Presentations/api_docs_v2.odp

# 3. Create the JSON snippet file
echo "Creating JSON snippet..."
cat << 'EOF' > /home/ga/Desktop/json_snippet.txt
{
  "user_id": "usr_8742_x9",
  "full_name": "Alex Rivera",
  "account_status": "active",
  "roles": [
    "sysadmin",
    "audit_viewer"
  ],
  "last_login": "2024-10-27T14:30:00Z"
}
EOF
sudo chown ga:ga /home/ga/Desktop/json_snippet.txt
sudo chmod 644 /home/ga/Desktop/json_snippet.txt

# 4. Record task start time and initial file state
date +%s > /tmp/task_start_time.txt
stat -c %Y /home/ga/Documents/Presentations/api_docs_v2.odp > /tmp/initial_file_mtime.txt

# 5. Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/api_docs_v2.odp > /tmp/impress_task.log 2>&1 &"

# 6. Wait for window and setup UI
wait_for_window "LibreOffice Impress" 60 || echo "WARNING: Window wait timeout"

# Focus and Maximize
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    echo "Focusing window ID: $wid"
    focus_window "$wid"
    # Maximize
    DISPLAY=:1 wmctrl -ir "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any recovery dialogs if they appear (Esc)
safe_xdotool ga :1 key Escape 2>/dev/null || true

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="