#!/bin/bash
echo "=== Setting up build_phylogenetic_tree task ==="

# 1. Clean previous task state
rm -rf /home/ga/UGENE_Data/results 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/results
chown -R ga:ga /home/ga/UGENE_Data/results

# Verify input data exists
if [ ! -s /home/ga/UGENE_Data/cytochrome_c_multispecies.fasta ]; then
    echo "ERROR: Cytochrome c FASTA file not found or empty"
    ls -la /home/ga/UGENE_Data/
    exit 1
fi

SEQ_COUNT=$(grep -c "^>" /home/ga/UGENE_Data/cytochrome_c_multispecies.fasta 2>/dev/null || echo "0")
echo "Input file has ${SEQ_COUNT} sequences"

# Record task start time for verification
touch /tmp/task_start_time

# 2. Kill any existing UGENE instance
pkill -f "ugene" 2>/dev/null || true
sleep 3
pkill -9 -f "ugene" 2>/dev/null || true
sleep 2

# 3. Launch UGENE
echo "Launching UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# 4. Wait for UGENE window to appear
TIMEOUT=90
ELAPSED=0
STARTED=false
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        echo "UGENE window detected after ${ELAPSED}s"
        STARTED=true
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ "$STARTED" = false ]; then
    echo "WARNING: UGENE window not detected, retrying launch..."
    pkill -f "ugene" 2>/dev/null || true
    sleep 2
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

    ELAPSED=0
    while [ $ELAPSED -lt 60 ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
            echo "UGENE window detected on retry after ${ELAPSED}s"
            STARTED=true
            break
        fi
        sleep 2
        ELAPSED=$((ELAPSED + 2))
    done
fi

if [ "$STARTED" = true ]; then
    sleep 5

    # Dismiss any startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1

    # 5. Maximize and focus the UGENE window
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 2
    fi

    # 6. Open the cytochrome c FASTA file using Ctrl+O
    echo "Opening cytochrome c FASTA file via File dialog..."
    DISPLAY=:1 xdotool key ctrl+o
    sleep 3

    # Type the file path in the file name field
    # In Qt file dialogs the file name input is near the bottom; click it to ensure focus
    # Coordinate: ~(662, 482) in 1280x720 → (993, 723) in 1920x1080
    DISPLAY=:1 xdotool mousemove 993 723 click 1
    sleep 0.5
    DISPLAY=:1 xdotool key ctrl+a
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers '/home/ga/UGENE_Data/cytochrome_c_multispecies.fasta'
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    sleep 3

    # 7. Handle the "Sequence Reading Options" dialog
    # The dialog has 4 radio buttons, default selection is first ("As separate sequences").
    # Use Down arrow to navigate to third option ("Join sequences into alignment").
    # Keyboard nav for radio buttons is robust across dialog size changes.
    echo "Selecting alignment viewing mode..."
    DISPLAY=:1 xdotool key Down
    sleep 0.3
    DISPLAY=:1 xdotool key Down
    sleep 0.3
    # Click OK button at ~(685, 488) in 1280x720 → (1028, 732) in 1920x1080
    DISPLAY=:1 xdotool mousemove 1028 732 click 1
    sleep 5

    echo "File loaded in alignment viewer"

    # 8. Take initial screenshot
    DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true
    echo "Initial screenshot saved"
else
    echo "ERROR: UGENE failed to start"
fi

echo "=== Task setup complete ==="
