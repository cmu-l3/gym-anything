#!/bin/bash
echo "=== Setting up add_exercise_video task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming validation)
date +%s > /tmp/task_start_time.txt

# Wait for wger to be fully available
wait_for_wger_page

# -----------------------------------------------------------------------
# Ensure a clean state by deleting the target video if it already exists
# -----------------------------------------------------------------------
echo "Cleaning up any pre-existing instances of the target video..."
docker exec wger-web python3 manage.py shell -c "
from wger.exercises.models import Video
deleted_count, _ = Video.objects.filter(url__icontains='wYREQkVtvEc').delete()
print(f'Deleted {deleted_count} pre-existing videos.')
" 2>/dev/null || true

# -----------------------------------------------------------------------
# Launch Firefox to the wger login page
# -----------------------------------------------------------------------
launch_firefox_to "http://localhost/en/user/login" 5

# Capture initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_start.png

# Verify screenshot was captured
if [ -f /tmp/task_start.png ]; then
    SIZE=$(stat -c %s /tmp/task_start.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo "=== Task setup complete ==="