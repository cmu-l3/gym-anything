#!/bin/bash
echo "=== Setting up modify_demo_experiment task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce
record_task_start
generate_nonce

# Ensure target directory exists
mkdir -p /home/ga/PsychoPyExperiments
chown ga:ga /home/ga/PsychoPyExperiments

# Remove any pre-existing output file
rm -f /home/ga/PsychoPyExperiments/stroop_modified.psyexp 2>/dev/null || true

# Ensure PsychoPy is running and focused on Builder
if ! is_psychopy_running; then
    echo "PsychoPy not running, launching..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 30
    sleep 3
    dismiss_psychopy_dialogs
fi

focus_builder
maximize_window "$(get_builder_window)"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

# Verify demos are available — if missing, attempt recovery
DEMO_DIR="/home/ga/PsychoPyExperiments/demos"
mkdir -p "$DEMO_DIR"

STROOP_DEMO=$(find "$DEMO_DIR" -iname "*stroop*" -name "*.psyexp" 2>/dev/null | head -1)

if [ -z "$STROOP_DEMO" ]; then
    echo "Stroop demo not found. Attempting to recover..."
    # Try pip-based path discovery (most reliable, avoids dbus abort)
    PSYCHOPY_PKG_DIR=$(pip3 show psychopy 2>/dev/null | grep "^Location:" | awk '{print $2}')
    if [ -n "$PSYCHOPY_PKG_DIR" ]; then
        PSYCHOPY_PKG_DIR="$PSYCHOPY_PKG_DIR/psychopy"
    fi
    # Fallback: search common paths
    if [ -z "$PSYCHOPY_PKG_DIR" ] || [ ! -d "$PSYCHOPY_PKG_DIR/demos" ]; then
        for candidate in /usr/local/lib/python3*/dist-packages/psychopy /usr/lib/python3*/dist-packages/psychopy /home/ga/.local/lib/python3*/dist-packages/psychopy; do
            if [ -d "$candidate/demos" ]; then
                PSYCHOPY_PKG_DIR="$candidate"
                break
            fi
        done
    fi
    if [ -n "$PSYCHOPY_PKG_DIR" ] && [ -d "$PSYCHOPY_PKG_DIR/demos" ]; then
        cp -r "$PSYCHOPY_PKG_DIR/demos/"* "$DEMO_DIR/" 2>/dev/null || true
        chown -R ga:ga "$DEMO_DIR"
        STROOP_DEMO=$(find "$DEMO_DIR" -iname "*stroop*" -name "*.psyexp" 2>/dev/null | head -1)
    fi
fi

if [ -n "$STROOP_DEMO" ]; then
    echo "Stroop demo found at: $STROOP_DEMO"
    echo "available" > /home/ga/.demo_status
else
    echo "ERROR: Stroop demo .psyexp file could not be found or recovered."
    echo "Available demos:"
    find "$DEMO_DIR" -name "*.psyexp" 2>/dev/null || echo "  (none)"
    echo "The task cannot be completed without the Stroop demo."
    echo "missing" > /home/ga/.demo_status
fi
chown ga:ga /home/ga/.demo_status

echo "=== Task setup complete ==="
echo "Task: Modify the Stroop demo experiment"
echo "Look for demos in /home/ga/PsychoPyExperiments/demos/ or PsychoPy Demos menu"
echo "Save modified version to: /home/ga/PsychoPyExperiments/stroop_modified.psyexp"
