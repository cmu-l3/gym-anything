#!/bin/bash
echo "=== Setting up create_spotlight_search task ==="

source /workspace/scripts/task_utils.sh

record_task_start
generate_nonce

# 1. Prepare Directories
STIM_DIR="/home/ga/PsychoPyExperiments/stimuli"
mkdir -p "$STIM_DIR"
chown ga:ga "$STIM_DIR"
mkdir -p /home/ga/PsychoPyExperiments/conditions
chown ga:ga /home/ga/PsychoPyExperiments/conditions

# 2. Generate Stimuli Images (Cluttered arrays)
# Using Python to generate decent "L" and "T" search arrays
cat << 'PY_STIM' | python3 -
import numpy as np
import matplotlib.pyplot as plt
import os
import random

stim_dir = "/home/ga/PsychoPyExperiments/stimuli"

def create_search_array(filename, target_present=True):
    fig, ax = plt.subplots(figsize=(10, 10), dpi=100)
    ax.set_xlim(0, 100)
    ax.set_ylim(0, 100)
    ax.axis('off')
    ax.set_facecolor('white')
    
    # Add distractor Ls
    for _ in range(150):
        x = random.uniform(5, 95)
        y = random.uniform(5, 95)
        rotation = random.choice([0, 90, 180, 270])
        ax.text(x, y, 'L', fontsize=15, rotation=rotation, ha='center', va='center')
        
    # Add target T
    if target_present:
        x = random.uniform(10, 90)
        y = random.uniform(10, 90)
        rotation = random.choice([0, 90, 180, 270])
        ax.text(x, y, 'T', fontsize=15, rotation=rotation, ha='center', va='center', color='red')
    
    plt.savefig(os.path.join(stim_dir, filename), bbox_inches='tight', pad_inches=0)
    plt.close()

create_search_array("array_1.png")
create_search_array("array_2.png")
create_search_array("array_3.png")
print("Generated 3 search arrays.")
PY_STIM

chown -R ga:ga "$STIM_DIR"

# 3. Clean up previous output
rm -f /home/ga/PsychoPyExperiments/spotlight_search.psyexp 2>/dev/null || true

# 4. Launch PsychoPy
if ! is_psychopy_running; then
    echo "PsychoPy not running, launching..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 45
    sleep 3
    dismiss_psychopy_dialogs
fi

focus_builder
maximize_window "$(get_builder_window)"

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Create a gaze-contingent spotlight experiment"
echo "Stimuli located in: $STIM_DIR"
echo "Save to: /home/ga/PsychoPyExperiments/spotlight_search.psyexp"