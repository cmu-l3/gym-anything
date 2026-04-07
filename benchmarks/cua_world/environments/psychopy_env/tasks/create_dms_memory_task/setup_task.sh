#!/bin/bash
echo "=== Setting up create_dms_memory_task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce
record_task_start
generate_nonce

# Create directory structure
mkdir -p /home/ga/PsychoPyExperiments/stimuli
mkdir -p /home/ga/PsychoPyExperiments/conditions
chown -R ga:ga /home/ga/PsychoPyExperiments

# Clean up previous run artifacts
rm -f /home/ga/PsychoPyExperiments/dms_task.psyexp 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/conditions/dms_conditions.csv 2>/dev/null || true

# Generate abstract stimuli (using Python to ensure they exist and are valid)
echo "Generating abstract stimuli..."
python3 << 'PYEOF'
import numpy as np
import matplotlib.pyplot as plt
from scipy.ndimage import gaussian_filter
import os

# Set seed for reproducibility of shapes (though noise is random)
np.random.seed(42)

output_dir = "/home/ga/PsychoPyExperiments/stimuli"
os.makedirs(output_dir, exist_ok=True)

print(f"Generating 20 stimuli in {output_dir}...")

for i in range(20):
    # Create random noise
    img = np.random.rand(128, 128)
    # Smooth it to make blobby abstract shapes
    img = gaussian_filter(img, sigma=4)
    # Threshold to make it binary-ish or high contrast
    img = (img - img.min()) / (img.max() - img.min())
    
    plt.figure(figsize=(2, 2), dpi=100)
    # Use different colormaps for variety
    cmap = 'plasma' if i % 2 == 0 else 'viridis'
    plt.imshow(img, cmap=cmap)
    plt.axis('off')
    plt.tight_layout(pad=0)
    filename = os.path.join(output_dir, f"shape_{i+1:02d}.png")
    plt.savefig(filename, bbox_inches='tight', pad_inches=0)
    plt.close()

print("Generation complete.")
PYEOF

# Ensure permissions
chown -R ga:ga /home/ga/PsychoPyExperiments/stimuli

# Ensure PsychoPy is running
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

echo "=== Task setup complete ==="
echo "Stimuli generated in: /home/ga/PsychoPyExperiments/stimuli/"