#!/bin/bash
set -e

echo "=== Setting up NLP Dependency Parse Task ==="

# 1. Prepare Environment
# ----------------------
# Create directories
su - ga -c "mkdir -p /home/ga/Diagrams /home/ga/Desktop" 2>/dev/null || true

# Clear previous artifacts
rm -f /home/ga/Diagrams/dependency_parse.drawio 2>/dev/null || true
rm -f /home/ga/Diagrams/dependency_parse.pdf 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# 2. Create Data File
# -------------------
# Create the CoNLL-U style parse data file
cat > /home/ga/Desktop/parse_data.txt << 'EOF'
# Sentence: The autonomous rover navigated the crater despite severe dust storms.
# ID  FORM        POS   HEAD  DEPREL
1     The         DET   3     det
2     autonomous  ADJ   3     amod
3     rover       NOUN  4     nsubj
4     navigated   VERB  0     root
5     the         DET   6     det
6     crater      NOUN  4     dobj
7     despite     ADP   10    case
8     severe      ADJ   10    amod
9     dust        NOUN  10    compound
10    storms      NOUN  4     obl
EOF

chown ga:ga /home/ga/Desktop/parse_data.txt
chmod 644 /home/ga/Desktop/parse_data.txt

# Record task start time
date +%s > /tmp/task_start_time.txt

# 3. Launch Application
# ---------------------
echo "Launching draw.io..."
# Kill any existing instances
pkill -f drawio 2>/dev/null || true
sleep 2

# Launch draw.io
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox > /dev/null 2>&1 &"

# Wait for window
echo "Waiting for window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done

# 4. Handle Dialogs
# -----------------
# Dismiss update dialog if it appears (common in AppImage)
sleep 5
echo "Attempting to dismiss update/startup dialogs..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize window
echo "Maximizing window..."
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "draw.io" 2>/dev/null || true

# 5. Capture Initial State
# ------------------------
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Task Data: /home/ga/Desktop/parse_data.txt"