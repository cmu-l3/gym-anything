#!/bin/bash
set -e
echo "=== Setting up concert_stage_plot_input_list task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create the requirements file on the Desktop
# This contains the source data the agent must visualize and transcribe
cat > /home/ga/Desktop/band_requirements.txt << 'EOF'
BAND TECH RIDER: "THE MIDNIGHT ALIBI"
DATE: OCT 2024
CONTACT: TOUR MANAGER

SECTION 1: STAGE PLOT REQUIREMENTS
Please create a diagram representing the stage layout (Top of page = Back of Stage).

Layout (Standard Rock Formation):
1. DRUMS: Center Stage, Rear.
   - Needs 8x8 Riser if available.
   - Needs Monitor: Drum Fill (Sub + Top) on Drummer's Left.
   - Needs AC Power Drop.

2. BASS STATION: Stage Right (Audience Left), Rear.
   - Bass Amp head + cabinet.
   - Needs AC Power Drop.

3. GUITAR STATION: Stage Left (Audience Right), Rear.
   - Guitar Amp combo on stand.
   - Needs AC Power Drop.

4. KEYS / BACKING VOX: Stage Right (Audience Left), Front.
   - Keyboard stand + Laptop.
   - Needs Monitor Wedge (Floor).
   - Needs AC Power Drop.

5. LEAD VOCALS: Center Stage, Front.
   - Mic Stand.
   - Needs Monitor Wedge (Floor).

NOTE: "Stage Right" means to the performer's right when facing the audience.
(On the diagram, Stage Right is on the LEFT side if Audience is at the bottom).

SECTION 2: INPUT LIST (AUDIO PATCH)
Please include this table on the diagram document.

| CH | INSTRUMENT    | MICROPHONE / DI      | STAND       |
|----|---------------|----------------------|-------------|
| 1  | Kick In       | Shure Beta 91A       | Internal    |
| 2  | Kick Out      | Shure Beta 52A       | Short Boom  |
| 3  | Snare Top     | Shure SM57           | Short Clip  |
| 4  | Snare Bottom  | Sennheiser e604      | Clip        |
| 5  | Hi-Hat        | Shure SM81           | Tall Boom   |
| 6  | Bass DI       | Radial J48           | -           |
| 7  | Bass Mic      | Electro-Voice RE20   | Short Boom  |
| 8  | Guitar Amp    | Sennheiser e906      | Z-Bar       |
| 9  | Keys (L/Mono) | Radial ProD2         | -           |
| 10 | Lead Vocal    | Shure Beta 58A       | Tall Boom   |

EOF
chown ga:ga /home/ga/Desktop/band_requirements.txt
chmod 644 /home/ga/Desktop/band_requirements.txt

# Clean up previous outputs if they exist
rm -f /home/ga/Desktop/midnight_alibi_rider.drawio
rm -f /home/ga/Desktop/midnight_alibi_rider.png

# Ensure draw.io is installed
if ! command -v drawio &>/dev/null && [ ! -f /opt/drawio/drawio ]; then
    echo "ERROR: draw.io not found"
    exit 1
fi

DRAWIO_BIN=$(command -v drawio || echo "/opt/drawio/drawio")

# Launch draw.io (Task starts with blank canvas)
# Using helper script if available, else direct launch
echo "Launching draw.io..."
if [ -f /usr/local/bin/drawio-launch ]; then
    /usr/local/bin/drawio-launch &
else
    su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio.log 2>&1 &"
fi

# Wait for window
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done

# Maximize window
sleep 3
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "draw.io" 2>/dev/null || true

# Dismiss "Create New/Open Existing" dialog to get to blank canvas
# Pressing Escape usually closes the startup modal and leaves a blank diagram
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="