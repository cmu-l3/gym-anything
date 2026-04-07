#!/bin/bash
echo "=== Setting up add_equipment_items task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure wger is responding
wait_for_wger_page

# Clean up target items if they already exist to guarantee a clean state
# Also retrieve the initial equipment count
echo "Cleaning up state and getting initial equipment count..."
INITIAL_COUNT_RAW=$(docker exec wger-web python3 manage.py shell -c "
from wger.exercises.models import Equipment
for name in ['Resistance Bands', 'TRX Suspension Trainer', 'Plyo Box']:
    Equipment.objects.filter(name__iexact=name).delete()
print(f'__COUNT__{Equipment.objects.count()}__COUNT__')
" 2>/dev/null)

INITIAL_COUNT=$(echo "$INITIAL_COUNT_RAW" | grep -o '__COUNT__[0-9]*__COUNT__' | sed 's/__COUNT__//g')
if [ -z "$INITIAL_COUNT" ]; then
    INITIAL_COUNT="0"
fi
echo "$INITIAL_COUNT" > /tmp/initial_count.txt
echo "Initial equipment count: $INITIAL_COUNT"

# Launch Firefox and navigate to the wger dashboard
launch_firefox_to "http://localhost/" 5

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="