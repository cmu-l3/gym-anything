#!/bin/bash
echo "=== Setting up code_simple_experiment task ==="

source /workspace/scripts/task_utils.sh

record_task_start
generate_nonce

# Ensure target directory exists
mkdir -p /home/ga/PsychoPyExperiments
chown ga:ga /home/ga/PsychoPyExperiments

rm -f /home/ga/PsychoPyExperiments/simple_rt.py 2>/dev/null || true

if ! is_psychopy_running; then
    echo "PsychoPy not running, launching..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 30
    sleep 3
    dismiss_psychopy_dialogs
fi

# This task requires Coder view — open it with multi-method fallback.
# PsychoPy opens Builder by default; Coder may not have a window yet.
focus_builder  # First ensure PsychoPy Builder is in front
maximize_window "$(get_builder_window)"
sleep 1

# Method 1: Ctrl+L (View > Coder shortcut in some versions)
echo "Opening Coder view (method 1: Ctrl+L)..."
DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
sleep 3
dismiss_psychopy_dialogs

CODER_WIN="$(get_coder_window)"
if [ -z "$CODER_WIN" ]; then
    # Method 2: Ctrl+Shift+C (alternative shortcut)
    echo "Coder not found, trying method 2: Ctrl+Shift+C..."
    focus_builder
    DISPLAY=:1 xdotool key ctrl+shift+c 2>/dev/null || true
    sleep 3
    dismiss_psychopy_dialogs
    CODER_WIN="$(get_coder_window)"
fi

if [ -z "$CODER_WIN" ]; then
    # Method 3: Menu navigation (View > Open Coder View)
    echo "Coder not found, trying method 3: menu navigation..."
    focus_builder
    DISPLAY=:1 xdotool key alt+v 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key c 2>/dev/null || true
    sleep 3
    dismiss_psychopy_dialogs
    CODER_WIN="$(get_coder_window)"
fi

if [ -n "$CODER_WIN" ]; then
    echo "Coder view opened successfully: $CODER_WIN"
    focus_coder
    maximize_window "$CODER_WIN"
else
    echo "WARNING: Could not open Coder view via any method — falling back to Builder"
    focus_builder
    maximize_window "$(get_builder_window)"
fi

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Write a simple PsychoPy experiment script in Coder view"
echo "Save to: /home/ga/PsychoPyExperiments/simple_rt.py"
