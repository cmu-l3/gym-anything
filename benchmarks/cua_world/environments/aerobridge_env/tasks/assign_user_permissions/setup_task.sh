#!/bin/bash
# setup_task.sh — pre_task hook for assign_user_permissions
# Creates the 'coordinator' user with no permissions and launches the admin panel.

echo "=== Setting up assign_user_permissions task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Aerobridge server to be ready
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# Record task start time
record_task_start

# Prepare the 'coordinator' user using Django script
echo "Configuring 'coordinator' user..."
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

try:
    from django.contrib.auth.models import User
    
    # Get or create the user
    user, created = User.objects.get_or_create(username='coordinator')
    
    # Set/Reset attributes to clean state
    user.set_password('coord2024!')
    user.is_staff = True
    user.is_superuser = False
    user.is_active = True
    user.save()
    
    # Clear all permissions and groups
    user.user_permissions.clear()
    user.groups.clear()
    
    print(f"User 'coordinator' configured: Created={created}, Staff={user.is_staff}, Perms={user.user_permissions.count()}")

except Exception as e:
    print(f"Setup Error: {e}")
    sys.exit(1)
PYEOF

# Launch Firefox to the User list page to save the agent some navigation steps
echo "Launching Firefox to User list..."
USER_LIST_URL="http://localhost:8000/admin/auth/user/"
launch_firefox "$USER_LIST_URL"

# Wait for window and maximize (using helper if available, else manual)
sleep 5
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/assign_permissions_start.png

echo "=== Setup complete ==="