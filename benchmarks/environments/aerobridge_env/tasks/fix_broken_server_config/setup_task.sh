#!/bin/bash
# setup_task.sh — pre_task hook for fix_broken_server_config
# Breaks the server configuration by corrupting the encryption key

echo "=== Setting up fix_broken_server_config task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Record true aircraft count (for verification later)
# We do this before breaking the app, while it might still be running or verifiable via script
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

AIRCRAFT_COUNT=$(/opt/aerobridge_venv/bin/python3 -c "
import os, sys, django
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
# Load env manually just in case
with open('/opt/aerobridge/.env') as f:
    for line in f:
        line = line.strip()
        if '=' in line and not line.startswith('#'):
            k, _, v = line.partition('=')
            os.environ.setdefault(k, v.strip(\"'\").strip('\"'))
django.setup()
try:
    from registry.models import Aircraft
    print(Aircraft.objects.count())
except:
    print('0')
" 2>/dev/null || echo "0")

echo "$AIRCRAFT_COUNT" > /tmp/expected_aircraft_count.txt
echo "Recorded expected aircraft count: $AIRCRAFT_COUNT"

# 3. Corrupt the configuration
echo "Corrupting CRYPTOGRAPHY_SALT in .env..."
# Replace valid key with garbage
sed -i "s|^CRYPTOGRAPHY_SALT=.*|CRYPTOGRAPHY_SALT='INVALID_BROKEN_KEY_CORRUPTED_VALUE'|" /opt/aerobridge/.env

# 4. Restart service to ensure it crashes and logs the error
echo "Restarting service to trigger failure..."
systemctl restart aerobridge
sleep 2

# Verify it's failed
if systemctl is-active --quiet aerobridge; then
    echo "WARNING: Service didn't fail immediately, stopping it."
    systemctl stop aerobridge
fi

# 5. Open Firefox to the broken page (will show connection error)
echo "Launching Firefox to show broken state..."
pkill -9 -f firefox 2>/dev/null || true
rm -f /home/ga/.mozilla/firefox/aerobridge.profile/lock 2>/dev/null || true

su - ga -c "DISPLAY=:1 setsid firefox --new-instance \
    -profile /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile \
    'http://localhost:8000/admin/' &"

sleep 5

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="
echo "Server is now BROKEN. Agent must fix it."