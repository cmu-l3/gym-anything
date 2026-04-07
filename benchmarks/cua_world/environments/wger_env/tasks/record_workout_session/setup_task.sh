#!/bin/bash
echo "=== Setting up record_workout_session task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Wait for wger web service to be available
wait_for_wger_page

# Extract initial database row counts for anti-gaming verification
cat > /tmp/initial_counts.py << 'EOF'
import json
from wger.manager.models import WorkoutSession, WorkoutLog
out = {
    'sessions': WorkoutSession.objects.count(),
    'logs': WorkoutLog.objects.count()
}
print(json.dumps(out))
EOF

docker cp /tmp/initial_counts.py wger-web:/tmp/initial_counts.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/initial_counts.py').read())" > /tmp/initial_counts.json

echo "Initial DB counts recorded:"
cat /tmp/initial_counts.json
echo ""

# Launch Firefox to the dashboard (uses utility function for cold start & snap permissions)
launch_firefox_to "http://localhost/en/dashboard" 8

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="