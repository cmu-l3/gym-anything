#!/bin/bash
echo "=== Setting up DRM False Memory Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce
record_task_start
generate_nonce

# 1. Clean up any previous attempts (Anti-Gaming)
rm -f /home/ga/PsychoPyExperiments/drm_false_memory.psyexp 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/conditions/drm_study_words.csv 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/conditions/drm_test_words.csv 2>/dev/null || true

# 2. Ensure directories exist with proper permissions
mkdir -p /home/ga/PsychoPyExperiments/conditions
chown -R ga:ga /home/ga/PsychoPyExperiments

# 3. Launch PsychoPy Builder if not running
if ! is_psychopy_running; then
    echo "PsychoPy not running, launching..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    
    # Wait for window (up to 60s)
    wait_for_psychopy 60
    sleep 5
    
    # Dismiss startup tips/dialogs
    dismiss_psychopy_dialogs
fi

# 4. Focus and Maximize Builder Window
focus_builder
maximize_window "$(get_builder_window)"

# 5. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Goal: Create a DRM false memory experiment."
echo "Save experiment to: /home/ga/PsychoPyExperiments/drm_false_memory.psyexp"
echo "Save conditions to: /home/ga/PsychoPyExperiments/conditions/drm_study_words.csv & drm_test_words.csv"