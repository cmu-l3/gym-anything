#!/bin/bash
# Visallo Setup Script (post_start hook)
# Starts Elasticsearch and Jetty with Visallo, configures Firefox (snap-aware)

echo "=== Setting up Visallo ==="

swapon /swapfile 2>/dev/null || true

export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
export VISALLO_DIR=/opt/visallo
export ES_HOME=/opt/elasticsearch
export JETTY_HOME=/opt/jetty
export PATH=$JAVA_HOME/bin:$PATH

# ── 1. Start Elasticsearch ──────────────────────────────────────────────────
echo "=== Starting Elasticsearch ==="
chown -R esuser:esuser ${ES_HOME} ${VISALLO_DIR}/datastore/elasticsearch
su - esuser -c "JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64 ES_HEAP_SIZE=512m ${ES_HOME}/bin/elasticsearch -d -p /tmp/es.pid" 2>/tmp/es_start.log || true

echo "Waiting for Elasticsearch..."
ES_READY=false
for i in $(seq 1 45); do
    if curl -s http://localhost:9200/ >/dev/null 2>&1; then
        echo "Elasticsearch ready after $((i*2))s"
        ES_READY=true
        break
    fi
    sleep 2
done

if [ "$ES_READY" = "false" ]; then
    echo "WARNING: Elasticsearch may not be ready. Checking logs..."
    cat /tmp/es_start.log 2>/dev/null || true
fi

# ── 2. Start Jetty with Visallo ─────────────────────────────────────────────
echo "=== Starting Jetty with Visallo ==="
rm -f /var/log/jetty.log

cd ${JETTY_HOME}
nohup java -Xms512m -Xmx2g \
    -DVISALLO_DIR=${VISALLO_DIR} \
    -Dvisallo.VISALLO_DIR=${VISALLO_DIR} \
    -jar ${JETTY_HOME}/start.jar \
    jetty.http.port=8080 \
    >> /var/log/jetty.log 2>&1 &

JETTY_PID=$!
echo $JETTY_PID > /tmp/jetty.pid
echo "Jetty started with PID $JETTY_PID"

echo "Waiting for Visallo..."
VISALLO_READY=false
for i in $(seq 1 90); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/ 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
        echo "Visallo ready after $((i*5))s (HTTP $HTTP_CODE)"
        VISALLO_READY=true
        break
    fi
    sleep 5
    if [ $((i % 6)) -eq 0 ]; then
        echo "  Waiting... $((i*5))s (HTTP ${HTTP_CODE:-000})"
    fi
done

if [ "$VISALLO_READY" = "false" ]; then
    echo "WARNING: Visallo may not be fully ready. Last HTTP code: $HTTP_CODE"
    echo "Jetty log tail:"
    tail -20 /var/log/jetty.log 2>/dev/null || true
fi

# ── 3. Load ICIJ Panama Papers data into Visallo ────────────────────────────
echo "=== Loading ICIJ data into Visallo ==="
if [ -f /workspace/scripts/load_data.py ] && [ "$VISALLO_READY" = "true" ]; then
    python3 /workspace/scripts/load_data.py \
        --entities /workspace/data/panama_papers_entities.csv \
        --officers /workspace/data/panama_papers_officers.csv \
        --relationships /workspace/data/panama_papers_relationships.csv 2>&1 || \
        echo "WARNING: Data loading had errors (non-fatal)"
else
    echo "WARNING: Skipping data load (Visallo not ready or script missing)"
fi

# ── 4. Set up Firefox profile (snap-aware) ──────────────────────────────────
echo "=== Setting up Firefox (snap-aware) ==="

# Firefox user.js content
FFPREFS='user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.warnOnQuit", false);
user_pref("browser.rights.3.shown", true);
user_pref("browser.startup.homepage", "http://localhost:8080/");
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
user_pref("privacy.trackingprotection.enabled", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
user_pref("browser.vpn_promo.enabled", false);
user_pref("sidebar.revamp", false);'

# Kill any existing Firefox
pkill -KILL -f firefox 2>/dev/null || true
pkill -KILL -f "Web Content" 2>/dev/null || true
sleep 3

# Set up regular profile dir
REGULAR_PROFILE="/home/ga/.mozilla/firefox"
sudo -u ga mkdir -p "$REGULAR_PROFILE/default-release"

cat > "$REGULAR_PROFILE/profiles.ini" << 'FFPROFILE'
[Profile0]
Name=default-release
IsRelative=1
Path=default-release
Default=1

[General]
StartWithLastProfile=1
Version=2
FFPROFILE

echo "$FFPREFS" > "$REGULAR_PROFILE/default-release/user.js"
chown -R ga:ga "$REGULAR_PROFILE"

# Warm-up launch to create snap profile structure
echo "Warm-up launch to initialize snap profile..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority firefox http://localhost:8080/ &" 2>/dev/null
sleep 12

# Dismiss any dialogs
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
sleep 2
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
sleep 1

# Kill warm-up
pkill -KILL -f firefox 2>/dev/null || true
pkill -KILL -f "Web Content" 2>/dev/null || true
sleep 3

# Inject user.js into snap profile (created by warm-up launch)
SNAP_PROFILE="/home/ga/snap/firefox/common/.mozilla/firefox"
if [ -d "$SNAP_PROFILE" ]; then
    echo "Snap profile found, injecting user.js"
    # Find the actual profile dir
    SNAP_PROF_DIR=$(find "$SNAP_PROFILE" -maxdepth 1 -type d -name "*.default*" 2>/dev/null | head -1)
    if [ -z "$SNAP_PROF_DIR" ]; then
        SNAP_PROF_DIR="$SNAP_PROFILE/default-release"
    fi
    sudo -u ga mkdir -p "$SNAP_PROF_DIR"
    echo "$FFPREFS" > "$SNAP_PROF_DIR/user.js"
    chown -R ga:ga "$SNAP_PROFILE"
    echo "Injected user.js into: $SNAP_PROF_DIR"
fi

# Clean ALL lock files everywhere
find /home/ga/.mozilla/ /home/ga/snap/firefox/ \
    -name "lock" -o -name ".parentlock" -o -name "parent.lock" \
    -o -name "singletonLock" -o -name "singletonCookie" -o -name "singletonSocket" \
    2>/dev/null | xargs rm -f 2>/dev/null || true

# ── 4. Launch Firefox with Visallo ──────────────────────────────────────────
echo "=== Launching Firefox ==="
# For snap Firefox, do NOT use --profile flag
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid firefox http://localhost:8080/ > /tmp/firefox_visallo.log 2>&1 &" 2>/dev/null
sleep 8

# Wait for Firefox window and maximize
FF_STARTED=false
for i in $(seq 1 20); do
    if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|visallo"; then
        FF_STARTED=true
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$FF_STARTED" = "true" ]; then
    sleep 1
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

echo "=== Visallo Setup Complete ==="
echo "Visallo: http://localhost:8080/"
echo "Login: type any username (username-only auth)"
echo "Elasticsearch: $(curl -s http://localhost:9200/ 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin).get("version",{}).get("number","unknown"))' 2>/dev/null || echo 'check status')"
