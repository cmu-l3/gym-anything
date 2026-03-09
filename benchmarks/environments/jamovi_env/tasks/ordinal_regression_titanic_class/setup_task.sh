#!/bin/bash
set -e
echo "=== Setting up Ordinal Regression Task ==="

# 1. Anti-gaming initialization
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous runs
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
rm -f /home/ga/Documents/Jamovi/Titanic_Ordinal.omv 2>/dev/null || true
rm -f /home/ga/Documents/Jamovi/ordinal_results.txt 2>/dev/null || true
sleep 2

# 3. Ensure Data Exists
DATASET="/home/ga/Documents/Jamovi/TitanicSurvival.csv"
if [ ! -f "$DATASET" ]; then
    echo "Restoring dataset..."
    cp "/opt/jamovi_datasets/TitanicSurvival.csv" "$DATASET"
    chown ga:ga "$DATASET"
fi

# 4. Launch Jamovi (Warm start)
# We launch it empty so the user has to open the file (part of the task)
echo "Starting Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi.log 2>&1 &"

# 5. Wait for Window
echo "Waiting for Jamovi window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
        echo "Jamovi window detected."
        break
    fi
    sleep 1
done

# 6. Maximize and Focus
# Use :ACTIVE: or find the ID to be safe, but typically "jamovi" works for the class
# Wait a bit for the window to actually map
sleep 5
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# 7. Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="