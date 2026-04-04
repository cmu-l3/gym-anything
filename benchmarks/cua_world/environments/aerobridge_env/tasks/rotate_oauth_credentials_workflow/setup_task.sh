#!/bin/bash
# setup_task.sh — pre_task hook for rotate_oauth_credentials_workflow

echo "=== Setting up rotate_oauth_credentials_workflow task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Aerobridge server
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# Record task start time
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_time

# Setup Database State:
# 1. Ensure 'Logistics_Fleet_Sync_v1' exists with specific config
# 2. Ensure 'Logistics_Fleet_Sync_v2' does NOT exist
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
with open('/opt/aerobridge/.env') as f:
    for line in f:
        line = line.strip()
        if '=' in line and not line.startswith('#'):
            k, _, v = line.partition('=')
            os.environ.setdefault(k, v.strip("'").strip('"'))
django.setup()

try:
    from oauth2_provider.models import Application
    from django.contrib.auth.models import User
    
    admin_user = User.objects.filter(username='admin').first()
    if not admin_user:
        print("Creating admin user for ownership...")
        admin_user = User.objects.create_superuser('admin', 'admin@example.com', 'adminpass123')

    # 1. Clean up target V2 app if it exists (from previous run)
    v2_count, _ = Application.objects.filter(name='Logistics_Fleet_Sync_v2').delete()
    if v2_count:
        print("Cleaned up existing v2 app.")

    # 2. Ensure V1 app exists with specific config
    app_v1, created = Application.objects.get_or_create(
        name='Logistics_Fleet_Sync_v1',
        defaults={
            'user': admin_user,
            'client_type': 'confidential',
            'authorization_grant_type': 'authorization-code',
            'redirect_uris': 'https://logistics-partner.com/oauth/callback https://backup.logistics-partner.com/complete/aerobridge',
            'algorithm': 'HS256'
        }
    )
    
    # Force update if it existed but might have wrong config
    if not created:
        app_v1.client_type = 'confidential'
        app_v1.authorization_grant_type = 'authorization-code'
        app_v1.redirect_uris = 'https://logistics-partner.com/oauth/callback https://backup.logistics-partner.com/complete/aerobridge'
        app_v1.save()
        print("Reset configuration for existing v1 app.")
    else:
        print("Created v1 app.")

    print(f"Setup complete. App '{app_v1.name}' ready (ID: {app_v1.client_id}).")

except Exception as e:
    print(f"Setup error: {e}")
    import traceback
    traceback.print_exc()
PYEOF

# Launch Firefox to the OAuth applications list for convenience, or just the main admin
echo "Launching Firefox..."
launch_firefox "http://localhost:8000/admin/"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="