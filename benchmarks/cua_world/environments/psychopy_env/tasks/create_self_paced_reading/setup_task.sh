#!/bin/bash
echo "=== Setting up create_self_paced_reading task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce for integrity
record_task_start
generate_nonce

# Create standard directory structure
mkdir -p /home/ga/PsychoPyExperiments/conditions
chown -R ga:ga /home/ga/PsychoPyExperiments

# Remove any pre-existing experiment file (clean slate)
rm -f /home/ga/PsychoPyExperiments/self_paced_reading.psyexp 2>/dev/null || true

# Create the conditions CSV with real garden-path sentences
# Source: Classic psycholinguistics stimuli (Bever 1970, Ferreira & Clifton 1986)
cat > /home/ga/PsychoPyExperiments/conditions/spr_sentences.csv << 'CSVEOF'
sentence_id,condition,sentence,question,correct_ans
1,gardenpath,The horse raced past the barn fell.,Did the horse fall?,y
2,control,The horse that was raced past the barn fell.,Did the horse fall?,y
3,gardenpath,The defendant examined by the lawyer turned out to be unreliable.,Was the defendant examined?,y
4,control,The defendant that was examined by the lawyer turned out to be unreliable.,Was the defendant examined?,y
5,gardenpath,The florist sent the flowers was very pleased.,Was the florist pleased?,y
6,control,The florist who was sent the flowers was very pleased.,Was the florist pleased?,y
7,gardenpath,The boat floated down the river sank.,Did the boat sink?,y
8,control,The boat that was floated down the river sank.,Did the boat sink?,y
9,gardenpath,The cotton clothing is usually made of grows in Mississippi.,Does cotton grow in Mississippi?,y
10,control,The cotton that clothing is usually made of grows in Mississippi.,Does cotton grow in Mississippi?,y
11,gardenpath,The editor articles were written by quit.,Did the editor quit?,y
12,control,The editor that articles were written by quit.,Did the editor quit?,y
CSVEOF

chown ga:ga /home/ga/PsychoPyExperiments/conditions/spr_sentences.csv

# Ensure PsychoPy is running and focused on Builder
if ! is_psychopy_running; then
    echo "PsychoPy not running, launching..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 60
    sleep 3
    dismiss_psychopy_dialogs
fi

focus_builder
maximize_window "$(get_builder_window)"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Create Self-Paced Reading Experiment"
echo "Conditions: /home/ga/PsychoPyExperiments/conditions/spr_sentences.csv"
echo "Output: /home/ga/PsychoPyExperiments/self_paced_reading.psyexp"