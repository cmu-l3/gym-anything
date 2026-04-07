#!/bin/bash
echo "=== Setting up Stop Signal Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
record_task_start
generate_nonce

# Create working directory
TASK_DIR="/home/ga/PsychoPyExperiments/sst_task"
mkdir -p "$TASK_DIR"
chown ga:ga "$TASK_DIR"

# Clean previous files to prevent gaming
rm -f "$TASK_DIR/stop_signal.psyexp" 2>/dev/null || true
rm -f "$TASK_DIR/sst_conditions.csv" 2>/dev/null || true

# Ensure assets exist
ASSETS_DIR="/home/ga/assets"
mkdir -p "$ASSETS_DIR"
if [ ! -f "$ASSETS_DIR/beep.wav" ]; then
    echo "Generating dummy beep.wav..."
    # Generate a simple beep using python/scipy if available, or just a dummy file
    # (PsychoPy needs a real audio file or it might error during validation, 
    # but for building the experiment, a 0-byte file often suffices if we don't run it.
    # However, better to make a valid wav header to be safe).
    python3 -c "
import wave, struct, math
with wave.open('$ASSETS_DIR/beep.wav', 'w') as obj:
    obj.setnchannels(1)
    obj.setsampwidth(2)
    obj.setframerate(44100)
    data = b''
    for i in range(4410): # 0.1 sec
        value = int(32767.0*math.sin(i*math.pi*2*(440.0/44100.0)))
        data += struct.pack('<h', value)
    obj.writeframesraw(data)
" 2>/dev/null || touch "$ASSETS_DIR/beep.wav"
fi
chown -R ga:ga "$ASSETS_DIR"

# Launch PsychoPy
if ! is_psychopy_running; then
    echo "Launching PsychoPy..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 45
    dismiss_psychopy_dialogs
fi

focus_builder
maximize_window "$(get_builder_window)"

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Create Stop Signal Task"
echo "Working Directory: $TASK_DIR"
echo "Asset: $ASSETS_DIR/beep.wav"