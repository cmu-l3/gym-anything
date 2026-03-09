#!/bin/bash
set -e
echo "=== Setting up export_registry_backup task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record task start time for anti-gaming (file modification check)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Clean up any previous run artifacts
OUTPUT_FILE="/home/ga/Documents/registry_backup.json"
if [ -f "$OUTPUT_FILE" ]; then
    echo "Removing pre-existing output file: $OUTPUT_FILE"
    rm -f "$OUTPUT_FILE"
fi

# Ensure the Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 3. Ensure Aerobridge server is running (standard environment state)
# Even though this is a CLI task, the app should be healthy
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# 4. Record initial database counts (for internal reference/debugging)
# We will compare the export against the DB state at the END of the task,
# but recording start state is good practice.
echo "Recording initial DB state..."
django_query "
from registry.models import Aircraft
print(f'Initial Aircraft count: {Aircraft.objects.count()}')
" 2>/dev/null || echo "Could not record initial counts"

# 5. Open a terminal for the agent
# The task requires CLI interaction, so start with a terminal open
echo "Opening terminal..."
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --maximize &"
    sleep 3
fi

# 6. Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="