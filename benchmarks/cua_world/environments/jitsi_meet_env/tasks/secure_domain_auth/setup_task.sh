#!/bin/bash
set -e

echo "=== Setting up Secure Domain Auth Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Reset .env to default insecure state
echo "Resetting environment configuration..."
cat > /home/ga/jitsi/.env << 'EOF'
# Jitsi Meet Default Configuration (Insecure)
CONFIG=~/.jitsi-meet-cfg
HTTP_PORT=8080
HTTPS_PORT=8443
TZ=UTC
PUBLIC_URL=http://localhost:8080
IP_ADDRESS=127.0.0.1

# Authentication (Disabled by default)
# ENABLE_AUTH=1
# ENABLE_GUESTS=1
# AUTH_TYPE=internal
# AUTH_USER=
# AUTH_PASSWORD=

# Passwords (Fixed for reproducibility)
JICOFO_AUTH_PASSWORD=a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4
JVB_AUTH_PASSWORD=b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5
JIBRI_RECORDER_PASSWORD=c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6
JIBRI_XMPP_PASSWORD=d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1
JIGASI_XMPP_PASSWORD=e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2
JIGASI_TRANSCRIBER_PASSWORD=f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3
EOF

chown ga:ga /home/ga/jitsi/.env

# 2. Ensure containers are running in the default state
echo "Ensuring Jitsi is running in default state..."
cd /home/ga/jitsi
docker compose up -d

# Wait for services to be healthy
wait_for_http "http://localhost:8080" 120

# 3. Clean up any previous moderator accounts in Prosody
echo "Cleaning up previous user accounts..."
PROSODY_CONTAINER=$(docker compose ps -q prosody)
if [ -n "$PROSODY_CONTAINER" ]; then
    # Unregister admin user if it exists (ignore errors if it doesn't)
    docker exec "$PROSODY_CONTAINER" prosodyctl --config /config/prosody.cfg.lua unregister admin meet.jitsi 2>/dev/null || true
fi

# 4. Open Firefox to the config location to give a hint/starting point
echo "Preparing Firefox..."
restart_firefox "file:///home/ga/jitsi/" 5
maximize_firefox
focus_firefox

# 5. Remove any old report
rm -f /home/ga/jitsi/auth_config_report.txt

# 6. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="