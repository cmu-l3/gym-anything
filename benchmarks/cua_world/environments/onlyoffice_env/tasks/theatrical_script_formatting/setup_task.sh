#!/bin/bash
set -euo pipefail

echo "=== Setting up Theatrical Script Formatting Task ==="
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
echo $(date +%s) > /tmp/task_start_time.txt

# Clean up any previous runs
cleanup_temp_files
kill_onlyoffice ga
sleep 1

# Prepare workspace
DOCS_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$DOCS_DIR"
RAW_FILE="$DOCS_DIR/cherry_orchard_raw.txt"
rm -f "$DOCS_DIR/cherry_orchard_script.docx" 2>/dev/null || true

# Generate the raw text excerpt
cat > "$RAW_FILE" << 'EOF'
ACT I

A room, which has always been called the nursery. One of the doors leads into Anya's room. Dawn, sun rises during the scene. May, the cherry trees in flower, but it is cold in the orchard with the frost of a morning. Windows closed.

Enter Dunyasha with a candle and Lopakhin with a book in his hand.

LOPAKHIN
The train is in, thank God. What time is it?

DUNYASHA
Nearly two.
[Puts out the candle.]
It's daylight already.

LOPAKHIN
The train was late! Two hours, at least.
[Yawns and stretches.]
I'm a pretty one; what a fool I've been. Came here on purpose to meet them at the station and dropped asleep... Dozed off as I sat in the chair. It's annoying... You might have waked me.
EOF

chown ga:ga "$RAW_FILE"

# Start ONLYOFFICE with the raw text file
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$RAW_FILE' > /tmp/onlyoffice.log 2>&1 &"

# Wait for the window to appear
wait_for_window "ONLYOFFICE" 30
sleep 3

# Focus and maximize the window to ensure full UI visibility for the agent
focus_onlyoffice_window
WID=$(get_onlyoffice_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi
sleep 2

# Take initial state screenshot
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="