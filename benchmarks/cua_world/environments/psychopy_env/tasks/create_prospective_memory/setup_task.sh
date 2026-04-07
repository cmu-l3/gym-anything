#!/bin/bash
echo "=== Setting up create_prospective_memory task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce
record_task_start
generate_nonce

# Create directories
mkdir -p /home/ga/Documents
mkdir -p /home/ga/PsychoPyExperiments/conditions
chown -R ga:ga /home/ga/Documents
chown -R ga:ga /home/ga/PsychoPyExperiments

# Clean up previous run artifacts
rm -f /home/ga/PsychoPyExperiments/conditions/pm_conditions.csv 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/prospective_memory.psyexp 2>/dev/null || true

# Generate Source Data (Real Lexical Decision stimuli)
# Format: word, type, default_ans
cat > /home/ga/Documents/lexical_source.csv << EOF
word,type,default_ans
logic,word,f
glorp,nonword,j
reason,word,f
plart,nonword,j
memory,word,f
skrun,nonword,j
focus,word,f
blipz,nonword,j
brain,word,f
crunki,nonword,j
visual,word,f
droft,nonword,j
spatial,word,f
mork,nonword,j
neuron,word,f
spiv,nonword,j
cortex,word,f
vlint,nonword,j
synapse,word,f
zorp,nonword,j
EOF
chown ga:ga /home/ga/Documents/lexical_source.csv

# Launch PsychoPy if not running
if ! is_psychopy_running; then
    echo "PsychoPy not running, launching..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 45
    sleep 3
    dismiss_psychopy_dialogs
fi

focus_builder
maximize_window "$(get_builder_window)"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Create Prospective Memory Experiment"
echo "Source Data: /home/ga/Documents/lexical_source.csv"
echo "Target CSV: /home/ga/PsychoPyExperiments/conditions/pm_conditions.csv"
echo "Target Exp: /home/ga/PsychoPyExperiments/prospective_memory.psyexp"