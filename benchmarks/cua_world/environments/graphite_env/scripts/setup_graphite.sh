#!/bin/bash
# NOTE: Do not use set -e here. curl may return non-zero during polling.

echo "=== Setting up Graphite Environment ==="

# Wait for desktop to be ready
sleep 5

# ===== Start Graphite Docker container =====
echo "=== Starting Graphite container ==="

# Stop any existing container
docker rm -f graphite 2>/dev/null || true

# Start the Graphite all-in-one container
docker run -d \
    --name graphite \
    --restart=always \
    -p 80:80 \
    -p 2003:2003 \
    -p 2004:2004 \
    -p 2023:2023 \
    -p 2024:2024 \
    -p 8125:8125/udp \
    -p 8126:8126 \
    graphiteapp/graphite-statsd:latest

# ===== Wait for Graphite web UI to be ready =====
echo "=== Waiting for Graphite web UI ==="
GRAPHITE_READY=false
for i in $(seq 1 60); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "Graphite web UI is ready (HTTP $HTTP_CODE)"
        GRAPHITE_READY=true
        break
    fi
    echo "Waiting for Graphite web... (HTTP $HTTP_CODE, $((i * 3))s elapsed)"
    sleep 3
done

if [ "$GRAPHITE_READY" = "false" ]; then
    echo "WARNING: Graphite web UI timeout, checking container status..."
    docker logs graphite --tail 30
fi

# ===== Wait for Carbon plaintext receiver =====
echo "=== Waiting for Carbon receiver on port 2003 ==="
CARBON_READY=false
for i in $(seq 1 30); do
    if nc -z localhost 2003 2>/dev/null; then
        echo "Carbon receiver is ready on port 2003"
        CARBON_READY=true
        break
    fi
    sleep 2
done

if [ "$CARBON_READY" = "false" ]; then
    echo "WARNING: Carbon receiver timeout"
fi

# ===== Configure and start collectd for real VM metrics =====
echo "=== Configuring collectd for real system metrics ==="

# Copy collectd config
cp /workspace/config/collectd.conf /etc/collectd/collectd.conf

# Start collectd to begin collecting real system metrics
systemctl restart collectd
sleep 2

if systemctl is-active --quiet collectd; then
    echo "collectd is running - collecting real system metrics"
else
    echo "WARNING: collectd failed to start, trying manual start..."
    collectd -C /etc/collectd/collectd.conf
fi

# ===== Feed real NAB data into Graphite =====
echo "=== Feeding real time-series data into Graphite ==="

# Use Python script to parse NAB CSV files and send to Carbon
python3 /workspace/scripts/feed_real_data.py

# ===== Rebuild metric index =====
echo "=== Rebuilding Graphite metric index ==="
sleep 5
docker exec graphite /opt/graphite/bin/build-index.sh 2>/dev/null || true
sleep 3

# ===== Wait for metrics to appear in Graphite =====
echo "=== Waiting for metrics to appear ==="
METRICS_READY=false
for i in $(seq 1 30); do
    METRIC_COUNT=$(curl -s "http://localhost/metrics/index.json" 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(len(data))
except:
    print(0)
" 2>/dev/null || echo "0")

    if [ "$METRIC_COUNT" -gt 5 ]; then
        echo "Metrics visible in Graphite: $METRIC_COUNT metrics found"
        METRICS_READY=true
        break
    fi
    echo "Waiting for metrics... ($METRIC_COUNT found so far, $((i * 5))s elapsed)"
    sleep 5
done

if [ "$METRICS_READY" = "false" ]; then
    echo "WARNING: Metrics not appearing yet, collectd may need more time"
fi

# ===== Verify data via Render API =====
echo "=== Verifying data via Render API ==="
# Check for NAB data
NAB_DATA=$(curl -s "http://localhost/render?target=servers.ec2_instance_1.cpu.utilization&from=-24h&format=json" 2>/dev/null || echo "[]")
echo "NAB EC2 CPU data check: $NAB_DATA" | head -c 200

# Check for collectd data
COLLECTD_DATA=$(curl -s "http://localhost/render?target=collectd.*&from=-1h&format=json" 2>/dev/null || echo "[]")
echo "collectd data check: $COLLECTD_DATA" | head -c 200

# ===== Set up Firefox =====
echo "=== Setting up Firefox ==="

# Create Firefox profile directory
su - ga -c "mkdir -p /home/ga/.mozilla/firefox/default-release"

# Create profiles.ini
cat > /home/ga/.mozilla/firefox/profiles.ini << 'PROFILES'
[Install4F96D1932A9F858E]
Default=default-release

[Profile0]
Name=default-release
IsRelative=1
Path=default-release
Default=1

[General]
StartWithLastProfile=1
Version=2
PROFILES

# Create user.js to disable first-run and set homepage
cat > /home/ga/.mozilla/firefox/default-release/user.js << 'USERJS'
user_pref("browser.startup.homepage", "http://localhost/");
user_pref("browser.startup.page", 1);
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("app.update.enabled", false);
user_pref("signon.rememberSignons", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("browser.tabs.warnOnClose", false);
USERJS

chown -R ga:ga /home/ga/.mozilla

# Create desktop shortcut
cat > /home/ga/Desktop/Graphite.desktop << 'DESKTOP'
[Desktop Entry]
Name=Graphite Monitor
Comment=Open Graphite Web Interface
Exec=firefox http://localhost/
Icon=firefox
Type=Application
Categories=Network;Monitor;
DESKTOP
chmod +x /home/ga/Desktop/Graphite.desktop
chown ga:ga /home/ga/Desktop/Graphite.desktop

# Warm-up launch: start Firefox, let it create profile, then close
echo "=== Warm-up Firefox launch ==="
su - ga -c "DISPLAY=:1 firefox --headless 'http://localhost/' &"
sleep 8
pkill -f "firefox.*headless" 2>/dev/null || true
sleep 2

# Launch Firefox to Graphite
echo "=== Launching Firefox ==="
su - ga -c "DISPLAY=:1 setsid firefox 'http://localhost/' > /tmp/firefox.log 2>&1 &"

# Wait for Firefox window
echo "=== Waiting for Firefox ==="
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|graphite\|mozilla"; then
        echo "Firefox detected"
        break
    fi
    sleep 1
done

# Maximize Firefox window
sleep 3
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|graphite\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    echo "Firefox maximized: $WID"
fi

echo "=== Graphite setup complete ==="
echo "Web UI: http://localhost/"
echo "Carbon plaintext: localhost:2003"
echo "Data sources: collectd (real VM metrics) + NAB (real EC2/server data)"
