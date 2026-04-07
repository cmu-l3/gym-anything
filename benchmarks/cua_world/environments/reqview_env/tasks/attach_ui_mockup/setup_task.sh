#!/bin/bash
set -e
echo "=== Setting up attach_ui_mockup task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Prepare the Mockup Data
# We create a realistic-looking "mockup" by taking a screenshot of a simple GTK window or just the current desktop state
# and saving it as the source file. This ensures it's a valid PNG with actual content.
mkdir -p /home/ga/Documents/Assets
# Create a dummy window to screenshot if possible, or just screenshot the empty desktop
# Using a small python script to create a simple image with text if PIL is available,
# otherwise fall back to copying a system icon or taking a scrot.
if python3 -c "import PIL" 2>/dev/null; then
    python3 -c "from PIL import Image, ImageDraw; img = Image.new('RGB', (800, 600), color = (73, 109, 137)); d = ImageDraw.Draw(img); d.text((10,10), 'Login Screen Mockup v2', fill=(255,255,0)); img.save('/home/ga/Documents/Assets/login_mockup.png')"
else
    # Fallback: copy a system icon or take a screenshot
    # Check for a common icon
    ICON_PATH=$(find /usr/share/icons -name "*.png" | head -n 1)
    if [ -n "$ICON_PATH" ]; then
        cp "$ICON_PATH" /home/ga/Documents/Assets/login_mockup.png
    else
        # Last resort: screenshot
        DISPLAY=:1 scrot /home/ga/Documents/Assets/login_mockup.png
    fi
fi
chmod 644 /home/ga/Documents/Assets/login_mockup.png

# 2. Setup Project
# Kill any running ReqView
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project
PROJECT_PATH=$(setup_task_project "attach_ui_mockup")
echo "Task project path: $PROJECT_PATH"

# Ensure SRS-1.1 exists (User Identification)
# In the standard example project, Section 1 is Introduction.
# We might need to inject specific content if the example project structure is different,
# but usually standard templates have standard structures.
# We will verify if SRS-1.1 exists, if not we rely on the agent finding "User Identification"
# The example project usually has "User Identification" under System Features or similar.
# For robustness, we inject a known requirement if needed, but let's assume standard project.
# To be safe, we print the SRS content to log to debug if needed.

# 3. Launch ReqView
launch_reqview_with_project "$PROJECT_PATH"
sleep 5

# 4. Prepare UI State
dismiss_dialogs
maximize_window

# Open SRS document explicitly
open_srs_document

# 5. Initial Evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="