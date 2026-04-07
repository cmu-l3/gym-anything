#!/bin/bash
echo "=== Setting up create_emotional_rating_task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time and nonce
record_task_start
generate_nonce

# 2. Prepare Directories
mkdir -p /home/ga/Documents/Stimuli
mkdir -p /home/ga/PsychoPyExperiments/conditions
chown -R ga:ga /home/ga/Documents
chown -R ga:ga /home/ga/PsychoPyExperiments

# 3. clean up previous attempts
rm -f /home/ga/PsychoPyExperiments/emotional_ratings.psyexp 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/conditions/faces.csv 2>/dev/null || true

# 4. Download Real Data (Public Domain Face Images)
# Using Wikimedia Commons samples to ensure realistic file handling
echo "Downloading stimuli..."
curl -L -o /home/ga/Documents/Stimuli/face_01.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/5/58/Face_with_a_blank_expression.jpg/320px-Face_with_a_blank_expression.jpg"
curl -L -o /home/ga/Documents/Stimuli/face_02.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/c/c2/Face_of_a_woman_with_a_blank_expression.jpg/320px-Face_of_a_woman_with_a_blank_expression.jpg"
curl -L -o /home/ga/Documents/Stimuli/face_03.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/8/8b/Face_of_a_man_with_a_blank_expression.jpg/320px-Face_of_a_man_with_a_blank_expression.jpg"

# Ensure images are owned by ga
chown ga:ga /home/ga/Documents/Stimuli/*.jpg

# 5. Launch PsychoPy if not running
if ! is_psychopy_running; then
    echo "PsychoPy not running, launching..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 60
    sleep 5
    dismiss_psychopy_dialogs
fi

# 6. Focus and Maximize Builder
focus_builder
maximize_window "$(get_builder_window)"

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Stimuli located in: /home/ga/Documents/Stimuli/"
echo "Task: Create 'emotional_ratings.psyexp' with 2 sliders (Valence, Arousal)"