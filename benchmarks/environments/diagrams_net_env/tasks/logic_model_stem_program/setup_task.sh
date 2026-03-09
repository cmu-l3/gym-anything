#!/bin/bash
set -e

echo "=== Setting up logic_model_stem_program task ==="

# 1. Create Directories
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/Diagrams
chown -R ga:ga /home/ga/Desktop /home/ga/Diagrams

# 2. Create the Grant Narrative Data File
# This contains the "Real Data" for the task
NARRATIVE_FILE="/home/ga/Desktop/grant_narrative.txt"
cat > "$NARRATIVE_FILE" << 'EOF'
PROJECT TITLE: FutureCoders Youth Pathway
GRANT NARRATIVE

The FutureCoders initiative is made possible by a $500,000 grant from the TechFoundation and the dedication of 12 full-time staff members. We have also partnered with the City Library System to provide venue space.

To achieve our goals, we will conduct three core activities: developing a new Python curriculum, running weekly after-school coding bootcamps, and hosting quarterly hackathons.

We anticipate these activities will reach significant scale. We expect to serve 200 high school students annually and train 50 certified instructors. In total, we will deliver 5,000 instructional hours.

As a result of this program, students will demonstrate improved math and logic scores. They will also report increased confidence in technical abilities.

Ultimately, our long-term vision is to create a more diverse STEM workforce and reduce the local unemployment rate.
EOF

chown ga:ga "$NARRATIVE_FILE"
chmod 644 "$NARRATIVE_FILE"

# 3. Clean up any previous runs
rm -f /home/ga/Diagrams/stem_logic_model.drawio
rm -f /home/ga/Diagrams/stem_logic_model.pdf
rm -f /tmp/task_result.json

# 4. Record Task Start Time (Anti-Gaming)
date +%s > /tmp/task_start_time.txt

# 5. Launch Text Editor with Narrative (so agent sees it immediately)
# This helps the agent understand the context right away
su - ga -c "DISPLAY=:1 xdg-open '$NARRATIVE_FILE'" &
sleep 2

# 6. Launch Draw.io (Pre-launch to save time, but blank)
# Using the launch script or direct binary
if [ -f /opt/drawio/drawio.AppImage ]; then
    echo "Pre-launching draw.io..."
    su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox &"
    
    # Wait for window
    for i in {1..20}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
            echo "draw.io window detected"
            break
        fi
        sleep 1
    done
    
    # Maximize
    DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 7. Take Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="