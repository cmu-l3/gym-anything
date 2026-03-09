#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up create_auditor_group task ==="

# 1. Ensure Aerobridge server is running
ensure_server_running
wait_for_aerobridge 60

# 2. Clean State: Remove the group if it already exists
echo "Cleaning up any existing 'Regulatory Auditors' group..."
django_query "
from django.contrib.auth.models import Group
try:
    g = Group.objects.filter(name='Regulatory Auditors')
    count = g.count()
    g.delete()
    print(f'Deleted {count} pre-existing groups.')
except Exception as e:
    print(f'Cleanup error: {e}')
"

# 3. Record Initial State (Anti-gaming)
# We expect 0 groups with this name.
INITIAL_COUNT=$(django_query "
from django.contrib.auth.models import Group
print(Group.objects.filter(name='Regulatory Auditors').count())
")
echo "$INITIAL_COUNT" > /tmp/initial_group_count.txt

# 4. Record task start time
record_task_start

# 5. Launch Firefox to Admin Login
# Kill any stale instances
kill_firefox
# Launch
launch_firefox "http://localhost:8000/admin/auth/group/"

# 6. Capture Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="