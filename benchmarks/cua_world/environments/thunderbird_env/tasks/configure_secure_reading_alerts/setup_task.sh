#!/bin/bash
set -euo pipefail

echo "=== Setting up Configure Secure Reading Alerts Task ==="

source /workspace/scripts/task_utils.sh || true

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Create the target audio file (a real, valid 16-bit PCM wav file)
DOCS_DIR="/home/ga/Documents"
mkdir -p "$DOCS_DIR"
WAV_FILE="$DOCS_DIR/urgent_bell.wav"

python3 -c "
import wave, struct, math
sample_rate = 44100
duration = 1.0 # seconds
freq = 880.0 # A5 note
obj = wave.open('$WAV_FILE', 'w')
obj.setnchannels(1)
obj.setsampwidth(2)
obj.setframerate(sample_rate)
for i in range(int(sample_rate * duration)):
    value = int(32767.0 * math.cos(freq * math.pi * float(i) / float(sample_rate)))
    data = struct.pack('<h', value)
    obj.writeframesraw(data)
obj.close()
"
chown ga:ga "$WAV_FILE"
echo "Created valid audio file at $WAV_FILE"

# 3. Record initial prefs.js state and modification time
PROFILE_DIR=$(find /home/ga/.thunderbird -maxdepth 1 -name "*default*" | head -n 1)
if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/prefs.js" ]; then
    stat -c %Y "$PROFILE_DIR/prefs.js" > /tmp/initial_prefs_mtime.txt
else
    echo "0" > /tmp/initial_prefs_mtime.txt
fi

# 4. Start Thunderbird if not already running
if ! pgrep -f "thunderbird" > /dev/null; then
    echo "Starting Thunderbird..."
    su - ga -c "DISPLAY=:1 thunderbird &"
    
    # Wait for the window to appear
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "Mozilla Thunderbird"; then
            echo "Thunderbird window detected."
            break
        fi
        sleep 1
    done
    sleep 3 # Give it time to fully render
fi

# 5. Maximize and focus Thunderbird
WID=$(DISPLAY=:1 wmctrl -l | grep -i "Thunderbird" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Click center of screen to ensure focus
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
sleep 1

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="