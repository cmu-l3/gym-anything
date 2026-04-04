#!/bin/bash
# setup_task.sh for ux_persona_card
set -e

echo "=== Setting up UX Persona Card Task ==="

# 1. Create Data Files
echo "Creating persona data..."
cat > /home/ga/Desktop/persona_data.txt << 'EOF'
PERSONA PROFILE
Name: Penny Parker
Role: Senior Project Manager
Quote: "I need to see the big picture without losing track of the details."

DEMOGRAPHICS
Age: 34
Education: MBA, PMP Certified
Location: Chicago, IL
Family: Married, 1 dog

BIO
Penny is a mid-level manager at a tech firm. She manages 3 cross-functional teams
and spends 60% of her day in meetings. She values efficiency over flashiness.

GOALS
- Reduce meeting times by 20%
- Centralize project documentation
- Automate weekly status reporting

FRUSTRATIONS
- Disconnected tools (Jira, Slack, Email)
- Micromanagement from stakeholders
- Chasing people for manual updates

PERSONALITY TRAITS
- Introvert <----> Extrovert (Lean: Extrovert/Right)
- Analytical <----> Creative (Lean: Analytical/Left)
- Tech-Savvy (High/Right)
EOF

# 2. Create Image Asset
# Using ImageMagick to create a stable local asset without external network dependency
echo "Creating profile photo..."
if command -v convert &> /dev/null; then
    convert -size 300x300 xc:lightblue \
        -fill white -draw "circle 150,150 150,100" \
        -fill black -draw "circle 120,130 125,130" \
        -fill black -draw "circle 180,130 185,130" \
        -no-curve -draw "path 'M 100,200 Q 150,250 200,200'" \
        /home/ga/Desktop/penny.jpg
else
    # Fallback if ImageMagick missing (unlikely in this env)
    echo "This is a placeholder image for Penny Parker" > /home/ga/Desktop/penny.jpg
fi

# Set permissions
chown ga:ga /home/ga/Desktop/persona_data.txt /home/ga/Desktop/penny.jpg

# 3. Clean previous run artifacts
rm -f /home/ga/Desktop/persona_card.drawio
rm -f /home/ga/Desktop/persona_card.png

# 4. Record Initial State
date +%s > /tmp/task_start_time.txt
ls -la /home/ga/Desktop/ > /tmp/initial_desktop_state.txt

# 5. Launch draw.io
# Find binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then DRAWIO_BIN="drawio";
elif [ -f /opt/drawio/drawio ]; then DRAWIO_BIN="/opt/drawio/drawio";
elif [ -f /usr/bin/drawio ]; then DRAWIO_BIN="/usr/bin/drawio";
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found"
    exit 1
fi

echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_launch.log 2>&1 &"

# Wait for window
echo "Waiting for window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss Startup Dialog (Escape creates blank diagram)
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="