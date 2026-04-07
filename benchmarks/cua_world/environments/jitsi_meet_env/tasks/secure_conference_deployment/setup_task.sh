#!/bin/bash
set -e

echo "=== Setting up secure_conference_deployment task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions in case task_utils.sh is incomplete
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi
if ! type wait_for_http &>/dev/null; then
    wait_for_http() {
        local url="$1" timeout="${2:-120}" elapsed=0
        while [ $elapsed -lt $timeout ]; do
            curl -sfk "$url" >/dev/null 2>&1 && return 0
            sleep 3; elapsed=$((elapsed + 3))
        done
        return 1
    }
fi
if ! type restart_firefox &>/dev/null; then
    restart_firefox() {
        pkill -f firefox 2>/dev/null || true; sleep 2
        pkill -9 -f firefox 2>/dev/null || true; sleep 1
        rm -f /home/ga/.mozilla/firefox/jitsi.profile/lock \
              /home/ga/.mozilla/firefox/jitsi.profile/.parentlock \
              /home/ga/snap/firefox/common/.mozilla/firefox/jitsi.profile/lock \
              /home/ga/snap/firefox/common/.mozilla/firefox/jitsi.profile/.parentlock 2>/dev/null || true
        DISPLAY=:1 nohup firefox "${1:-http://localhost:8080}" >/tmp/firefox_task.log 2>&1 &
        sleep "${2:-8}"
    }
fi
if ! type maximize_firefox &>/dev/null; then
    maximize_firefox() {
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    }
fi
if ! type focus_firefox &>/dev/null; then
    focus_firefox() {
        DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true
        sleep 0.5
    }
fi

# ── 1. Delete stale outputs BEFORE recording timestamp ──────────────────────
rm -f /home/ga/secure_conference_report.txt
rm -f /home/ga/.jitsi-meet-cfg/web/custom-interface_config.js
echo "" | DISPLAY=:1 xclip -selection clipboard 2>/dev/null || true

# ── 2. Record task start time ───────────────────────────────────────────────
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# ── 3. Rewrite docker-compose.yml with variable interpolation for auth ──────
# The original docker-compose.yml has hardcoded ENABLE_AUTH=0.
# We replace it with ${ENABLE_AUTH:-0} so that .env changes take effect.
cat > /home/ga/jitsi/docker-compose.yml << 'COMPOSEOF'
services:
  # Jitsi Meet web frontend
  web:
    image: jitsi/web:stable-9753
    restart: unless-stopped
    ports:
      - '8080:80'
      - '8443:443'
    volumes:
      - /home/ga/.jitsi-meet-cfg/web:/config:Z
      - /home/ga/.jitsi-meet-cfg/transcripts:/usr/share/jitsi-meet/transcripts:Z
    environment:
      - ENABLE_AUTH=${ENABLE_AUTH:-0}
      - AUTH_TYPE=${AUTH_TYPE:-}
      - ENABLE_GUESTS=${ENABLE_GUESTS:-1}
      - ENABLE_LETSENCRYPT=0
      - ENABLE_HTTP_REDIRECT=0
      - ENABLE_HSTS=0
      - ENABLE_RECORDING=0
      - ENABLE_LIVESTREAMING=0
      - ENABLE_TRANSCRIPTIONS=0
      - DISABLE_HTTPS=1
      - HTTP_PORT=80
      - HTTPS_PORT=443
      - TZ=UTC
      - PUBLIC_URL=http://localhost:8080
      - BOSH_RELATIVE=true
      - ENABLE_XMPP_WEBSOCKET=0
      - XMPP_DOMAIN=meet.jitsi
      - XMPP_AUTH_DOMAIN=auth.meet.jitsi
      - XMPP_BOSH_URL_BASE=http://xmpp.meet.jitsi:5280
      - XMPP_MUC_DOMAIN=muc.meet.jitsi
      - XMPP_INTERNAL_MUC_DOMAIN=internal-muc.meet.jitsi
      - XMPP_GUEST_DOMAIN=guest.meet.jitsi
      - JICOFO_AUTH_USER=focus
      - JICOFO_AUTH_PASSWORD=${JICOFO_AUTH_PASSWORD}
      - JVB_AUTH_USER=jvb
      - JVB_AUTH_PASSWORD=${JVB_AUTH_PASSWORD}
      - JIBRI_RECORDER_PASSWORD=${JIBRI_RECORDER_PASSWORD}
      - JIBRI_XMPP_PASSWORD=${JIBRI_XMPP_PASSWORD}
    networks:
      meet.jitsi:
        aliases:
          - meet.jitsi

  # XMPP server
  prosody:
    image: jitsi/prosody:stable-9753
    restart: unless-stopped
    expose:
      - '5222'
      - '5269'
      - '5280'
      - '5347'
    volumes:
      - /home/ga/.jitsi-meet-cfg/prosody/config:/config:Z
      - /home/ga/.jitsi-meet-cfg/prosody/prosody-plugins-custom:/prosody-plugins-custom:Z
    environment:
      - ENABLE_AUTH=${ENABLE_AUTH:-0}
      - AUTH_TYPE=${AUTH_TYPE:-}
      - ENABLE_GUESTS=${ENABLE_GUESTS:-1}
      - ENABLE_LOBBY=1
      - ENABLE_AV_MODERATION=1
      - XMPP_DOMAIN=meet.jitsi
      - XMPP_AUTH_DOMAIN=auth.meet.jitsi
      - XMPP_GUEST_DOMAIN=guest.meet.jitsi
      - XMPP_MUC_DOMAIN=muc.meet.jitsi
      - XMPP_INTERNAL_MUC_DOMAIN=internal-muc.meet.jitsi
      - XMPP_HIDDEN_DOMAIN=hidden.meet.jitsi
      - XMPP_RECORDER_DOMAIN=recorder.meet.jitsi
      - JICOFO_AUTH_USER=focus
      - JICOFO_AUTH_PASSWORD=${JICOFO_AUTH_PASSWORD}
      - JVB_AUTH_USER=jvb
      - JVB_AUTH_PASSWORD=${JVB_AUTH_PASSWORD}
      - JIBRI_RECORDER_PASSWORD=${JIBRI_RECORDER_PASSWORD}
      - JIBRI_XMPP_PASSWORD=${JIBRI_XMPP_PASSWORD}
      - JIGASI_XMPP_PASSWORD=${JIGASI_XMPP_PASSWORD}
      - JIGASI_TRANSCRIBER_PASSWORD=${JIGASI_TRANSCRIBER_PASSWORD}
      - TZ=UTC
      - LOG_LEVEL=info
    networks:
      meet.jitsi:
        aliases:
          - xmpp.meet.jitsi

  # Conference focus component
  jicofo:
    image: jitsi/jicofo:stable-9753
    restart: unless-stopped
    volumes:
      - /home/ga/.jitsi-meet-cfg/jicofo:/config:Z
    environment:
      - ENABLE_AUTH=${ENABLE_AUTH:-0}
      - AUTH_TYPE=${AUTH_TYPE:-}
      - ENABLE_LOBBY=1
      - XMPP_DOMAIN=meet.jitsi
      - XMPP_SERVER=xmpp.meet.jitsi
      - XMPP_AUTH_DOMAIN=auth.meet.jitsi
      - XMPP_INTERNAL_MUC_DOMAIN=internal-muc.meet.jitsi
      - XMPP_MUC_DOMAIN=muc.meet.jitsi
      - JICOFO_AUTH_USER=focus
      - JICOFO_AUTH_PASSWORD=${JICOFO_AUTH_PASSWORD}
      - JVB_AUTH_USER=jvb
      - JVB_AUTH_PASSWORD=${JVB_AUTH_PASSWORD}
      - JIBRI_RECORDER_PASSWORD=${JIBRI_RECORDER_PASSWORD}
      - JIBRI_XMPP_PASSWORD=${JIBRI_XMPP_PASSWORD}
      - TZ=UTC
      - JICOFO_ENABLE_HEALTH_CHECKS=true
    depends_on:
      - prosody
    networks:
      meet.jitsi:

  # Video bridge (SFU)
  jvb:
    image: jitsi/jvb:stable-9753
    restart: unless-stopped
    ports:
      - '10000:10000/udp'
      - '4443:4443'
    volumes:
      - /home/ga/.jitsi-meet-cfg/jvb:/config:Z
    environment:
      - XMPP_AUTH_DOMAIN=auth.meet.jitsi
      - XMPP_INTERNAL_MUC_DOMAIN=internal-muc.meet.jitsi
      - XMPP_SERVER=xmpp.meet.jitsi
      - JVB_AUTH_USER=jvb
      - JVB_AUTH_PASSWORD=${JVB_AUTH_PASSWORD}
      - JVB_BREWERY_MUC=jvbbrewery
      - JVB_PORT=10000
      - JVB_TCP_HARVESTER_DISABLED=true
      - JVB_ADVERTISE_IPS=127.0.0.1
      - JICOFO_AUTH_PASSWORD=${JICOFO_AUTH_PASSWORD}
      - COLIBRI_REST_ENABLED=true
      - JVB_ENABLE_APIS=rest,colibri
      - TZ=UTC
    depends_on:
      - prosody
    networks:
      meet.jitsi:

networks:
  meet.jitsi:
    driver: bridge
COMPOSEOF

chown ga:ga /home/ga/jitsi/docker-compose.yml

# ── 4. Reset .env to clean non-auth state ───────────────────────────────────
cat > /home/ga/jitsi/.env << 'ENVEOF'
# Jitsi Meet Environment Configuration
JICOFO_AUTH_PASSWORD=a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4
JVB_AUTH_PASSWORD=b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5
JIBRI_RECORDER_PASSWORD=c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6
JIBRI_XMPP_PASSWORD=d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1
JIGASI_XMPP_PASSWORD=e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2
JIGASI_TRANSCRIBER_PASSWORD=f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3

# Authentication settings
ENABLE_AUTH=0
AUTH_TYPE=
ENABLE_GUESTS=1
ENVEOF

chown ga:ga /home/ga/jitsi/.env

# ── 5. Clear custom config files ────────────────────────────────────────────
mkdir -p /home/ga/.jitsi-meet-cfg/web
rm -f /home/ga/.jitsi-meet-cfg/web/custom-config.js
rm -f /home/ga/.jitsi-meet-cfg/web/custom-interface_config.js
touch /home/ga/.jitsi-meet-cfg/web/custom-config.js
touch /home/ga/.jitsi-meet-cfg/web/custom-interface_config.js
chown ga:ga /home/ga/.jitsi-meet-cfg/web/custom-config.js
chown ga:ga /home/ga/.jitsi-meet-cfg/web/custom-interface_config.js

# ── 6. Restart Docker services with clean state ─────────────────────────────
echo "Restarting Jitsi services with clean config..."
cd /home/ga/jitsi
docker compose down 2>/dev/null || true
sleep 3
docker compose up -d

# Wait for Jitsi to be accessible
if ! wait_for_http "http://localhost:8080" 300; then
    echo "ERROR: Jitsi Meet not reachable after restart"
    docker compose logs --tail=30 || true
    exit 1
fi

# Verify all 4 containers are running (not just web endpoint)
echo "Verifying container health..."
for svc in web prosody jicofo jvb; do
    SVC_ID=$(docker compose ps -q "$svc" 2>/dev/null || echo "")
    if [ -z "$SVC_ID" ]; then
        echo "ERROR: $svc container not found, retrying full restart..."
        docker compose down 2>/dev/null || true
        sleep 5
        docker compose up -d
        wait_for_http "http://localhost:8080" 300
        break
    fi
    SVC_RUNNING=$(docker inspect -f '{{.State.Running}}' "$SVC_ID" 2>/dev/null || echo "false")
    if [ "$SVC_RUNNING" != "true" ]; then
        echo "WARNING: $svc is not running, forcing restart..."
        docker compose down 2>/dev/null || true
        sleep 5
        docker compose up -d
        wait_for_http "http://localhost:8080" 300
        break
    fi
    echo "  $svc: running"
done
echo "Jitsi Meet is running at http://localhost:8080 (no authentication)"

# ── 7. Clear any existing admin user from prosody ───────────────────────────
PROSODY_CONTAINER=$(docker compose ps -q prosody 2>/dev/null || echo "")
if [ -n "$PROSODY_CONTAINER" ]; then
    docker exec "$PROSODY_CONTAINER" prosodyctl --config /config/prosody.cfg.lua \
        deluser admin@meet.jitsi 2>/dev/null || true
fi

# ── 8. Kill Epiphany if running ─────────────────────────────────────────────
pkill -f epiphany 2>/dev/null || true
pkill -f "Web Content" 2>/dev/null || true
sleep 1

# ── 9. Open Firefox at Jitsi homepage ───────────────────────────────────────
restart_firefox "http://localhost:8080" 10
maximize_firefox
focus_firefox

# ── 10. Take initial screenshot ─────────────────────────────────────────────
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="
echo "Jitsi Meet is running at http://localhost:8080 (no authentication, default UI)"
echo "Task: Configure authenticated branded conferences and verify end-to-end flow"
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"
