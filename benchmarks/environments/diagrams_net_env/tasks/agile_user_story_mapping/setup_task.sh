#!/bin/bash
set -e
echo "=== Setting up Agile User Story Mapping Task ==="

# 1. Prepare the Requirements Document
REQUIREMENTS_FILE="/home/ga/Desktop/lumina_requirements.txt"
cat > "$REQUIREMENTS_FILE" << 'EOF'
PRODUCT REQUIREMENTS DOCUMENT: LUMINA SMART LIGHT SYSTEM

1. USER ACTIVITIES (THE BACKBONE)
The user journey consists of four main phases:
- Onboarding (getting started)
- Device Control (daily usage)
- Automation (smart features)
- System Settings (admin tasks)

2. RELEASE SCOPE

[MVP - Must Have]
For the initial launch, the focus is purely on basic usability.
- Under Onboarding: Users must be able to "Create Account" and "Pair First Hub".
- Under Device Control: Users need to "Toggle Light On/Off" and "Adjust Brightness".
- Under Automation: No automation features in MVP.
- Under System Settings: Users need to "View App Version".

[Release 1.5 - Enhancements]
This update adds convenience.
- Under Onboarding: Add "Social Login (Google)".
- Under Device Control: Add "Color Temperature Tuning".
- Under Automation: Users can "Create Daily Schedule" and "Set Vacation Mode".
- Under System Settings: Add "Manage Guest Access".

[Future - V2.0]
Advanced features for power users.
- Under Device Control: "Music Sync Mode".
- Under Automation: "Geofencing Trigger" (lights on when arriving home).
- Under System Settings: "Energy Usage Reports".
EOF
chmod 644 "$REQUIREMENTS_FILE"
chown ga:ga "$REQUIREMENTS_FILE"

# 2. Clean up previous artifacts
rm -f /home/ga/Diagrams/lumina_story_map.drawio
rm -f /home/ga/Diagrams/lumina_story_map.png
mkdir -p /home/ga/Diagrams
chown ga:ga /home/ga/Diagrams

# 3. Record start time and state
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_drawio_count

# 4. Launch Applications
# Launch Text Editor with Requirements
su - ga -c "DISPLAY=:1 gedit '$REQUIREMENTS_FILE' &"
sleep 2

# Launch draw.io (blank)
if [ -f /opt/drawio/drawio.AppImage ]; then
    su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox &"
else
    echo "ERROR: draw.io not found"
    exit 1
fi

# 5. Window Management
sleep 8
# Attempt to arrange windows side-by-side
# Get Window IDs
DRAWIO_WID=$(DISPLAY=:1 wmctrl -l | grep -i "draw.io" | awk '{print $1}' | head -1)
GEDIT_WID=$(DISPLAY=:1 wmctrl -l | grep -i "gedit" | awk '{print $1}' | head -1)

if [ -n "$DRAWIO_WID" ]; then
    # Move draw.io to left half
    DISPLAY=:1 wmctrl -i -r "$DRAWIO_WID" -e 0,0,0,960,1080
    DISPLAY=:1 wmctrl -i -a "$DRAWIO_WID"
    
    # Dismiss update dialog if it appears (common in draw.io appimage)
    sleep 1
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
fi

if [ -n "$GEDIT_WID" ]; then
    # Move gedit to right half
    DISPLAY=:1 wmctrl -i -r "$GEDIT_WID" -e 0,960,0,960,1080
fi

# 6. Capture Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="