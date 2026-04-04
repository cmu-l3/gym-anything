#!/bin/bash
set -e
echo "=== Setting up LDA Heart Disease Task ==="

# 1. Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Prepare Data
DATA_DIR="/home/ga/Documents/JASP"
DATA_FILE="$DATA_DIR/Heart_Disease.csv"
mkdir -p "$DATA_DIR"

# Check if dataset exists, if not download it
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading Heart Disease dataset..."
    wget -q -O "$DATA_FILE" "https://raw.githubusercontent.com/jasp-stats/jasp-desktop/master/Resources/Data%20Sets/Data%20Library/8.%20Machine%20Learning/Heart%20Disease.csv"
    
    # Validation
    if [ ! -f "$DATA_FILE" ] || [ $(stat -c%s "$DATA_FILE") -lt 1000 ]; then
        echo "ERROR: Failed to download Heart_Disease.csv"
        # Fallback to creating a dummy file if network fails (to prevent total crash, though task will be harder)
        # In production, we'd exit 1, but for robustness here we warn.
        exit 1
    fi
fi
chown -R ga:ga "$DATA_DIR"
chmod 644 "$DATA_FILE"

# 3. Ensure JASP is running
# Using setsid to detach from shell
if ! pgrep -f "org.jaspstats.JASP" > /dev/null; then
    echo "Starting JASP..."
    su - ga -c "setsid /usr/local/bin/launch-jasp &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
            echo "JASP window detected"
            break
        fi
        sleep 1
    done
    sleep 5
fi

# 4. Maximize and Focus
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# 5. Dismiss any startup dialogs (Esc, Enter)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# 6. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="