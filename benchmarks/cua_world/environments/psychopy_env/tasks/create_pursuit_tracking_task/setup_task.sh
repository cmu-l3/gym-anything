#!/bin/bash
echo "=== Setting up create_pursuit_tracking_task ==="

source /workspace/scripts/task_utils.sh

record_task_start
generate_nonce

# Create directories
mkdir -p /home/ga/PsychoPyExperiments/assets
chown -R ga:ga /home/ga/PsychoPyExperiments

# Generate the trajectory CSV file (Lissajous curve)
# This ensures we have real, complex data to work with
python3 -c "
import numpy as np
import pandas as pd

# Generate 600 frames (10 seconds at 60Hz)
t = np.linspace(0, 10, 600)
# Lissajous figure: x = A sin(at + delta), y = B sin(bt)
x = 0.4 * np.sin(1.5 * t + np.pi/2)
y = 0.4 * np.sin(1.0 * t)

df = pd.DataFrame({'x': x, 'y': y})
df.to_csv('/home/ga/PsychoPyExperiments/assets/trajectory.csv', index=False)
print('Generated trajectory.csv with 600 rows')
"

# Set permissions
chown ga:ga /home/ga/PsychoPyExperiments/assets/trajectory.csv
chmod 644 /home/ga/PsychoPyExperiments/assets/trajectory.csv

# Remove any pre-existing output file
rm -f /home/ga/PsychoPyExperiments/pursuit_tracking.psyexp 2>/dev/null || true

# Ensure PsychoPy is running
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
echo "Task: Create a pursuit tracking experiment"
echo "Trajectory file: /home/ga/PsychoPyExperiments/assets/trajectory.csv"
echo "Save to: /home/ga/PsychoPyExperiments/pursuit_tracking.psyexp"