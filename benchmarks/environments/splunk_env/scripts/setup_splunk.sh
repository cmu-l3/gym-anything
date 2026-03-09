#!/bin/bash
# NOTE: Do not use set -e here. curl/wget may return non-zero codes that
# are handled gracefully, and wait functions return 1 on timeout.

echo "=== Setting up Splunk Enterprise ==="

# Wait for desktop to be ready
sleep 5

# Start Splunk Enterprise non-interactively
echo "=== Starting Splunk ==="
/opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt

# Wait for Splunk web interface to be ready
echo "=== Waiting for Splunk web interface ==="
SPLUNK_WEB_READY=false
for i in $(seq 1 24); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "303" ] || [ "$HTTP_CODE" = "302" ]; then
        echo "Splunk web interface is ready (HTTP $HTTP_CODE)"
        SPLUNK_WEB_READY=true
        break
    fi
    echo "Waiting for Splunk web... (HTTP $HTTP_CODE, $((i * 5))s elapsed)"
    sleep 5
done

if [ "$SPLUNK_WEB_READY" = "false" ]; then
    echo "WARNING: Splunk web interface timeout, continuing anyway..."
fi

# Wait for splunkd REST API
echo "=== Waiting for Splunk REST API ==="
SPLUNK_API_READY=false
for i in $(seq 1 20); do
    API_RESPONSE=$(curl -sk -u admin:SplunkAdmin1! https://localhost:8089/services/server/info 2>/dev/null || true)
    if echo "$API_RESPONSE" | grep -q "server_name"; then
        echo "Splunk REST API is ready"
        SPLUNK_API_READY=true
        break
    fi
    sleep 3
done

if [ "$SPLUNK_API_READY" = "false" ]; then
    echo "WARNING: Splunk REST API timeout, continuing anyway..."
fi

# Create custom indexes for different data types
echo "=== Creating indexes ==="
/opt/splunk/bin/splunk add index security_logs -auth admin:SplunkAdmin1! || true
/opt/splunk/bin/splunk add index web_logs -auth admin:SplunkAdmin1! || true
/opt/splunk/bin/splunk add index system_logs -auth admin:SplunkAdmin1! || true
/opt/splunk/bin/splunk add index tutorial -auth admin:SplunkAdmin1! || true
/opt/splunk/bin/splunk add index network_logs -auth admin:SplunkAdmin1! || true

# Ingest the real-world data
echo "=== Ingesting log data ==="

# Ingest tutorial data (Buttercup Games web access, secure, vendor logs)
if [ -d /opt/splunk_data/tutorial ]; then
    for f in /opt/splunk_data/tutorial/*.log /opt/splunk_data/tutorial/**/*.log; do
        if [ -f "$f" ]; then
            /opt/splunk/bin/splunk add oneshot "$f" -index tutorial -auth admin:SplunkAdmin1! || true
            echo "Ingested: $f"
        fi
    done
    # Also try zip contents if they were in subdirectories
    find /opt/splunk_data/tutorial -name "*.log" -o -name "*.csv" | while read -r logfile; do
        /opt/splunk/bin/splunk add oneshot "$logfile" -index tutorial -auth admin:SplunkAdmin1! 2>/dev/null || true
    done
fi

# Ingest auth.log (real SSH brute force data)
if [ -f /opt/splunk_data/security/auth.log ]; then
    /opt/splunk/bin/splunk add oneshot /opt/splunk_data/security/auth.log -index security_logs -sourcetype linux_secure -auth admin:SplunkAdmin1! || true
    echo "Ingested auth.log"
fi

# Ingest SSH logs (Loghub)
find /opt/splunk_data/security -name "*.log" -o -name "SSH*" | while read -r logfile; do
    if [ -f "$logfile" ] && [ "$logfile" != "/opt/splunk_data/security/auth.log" ]; then
        /opt/splunk/bin/splunk add oneshot "$logfile" -index security_logs -sourcetype syslog -auth admin:SplunkAdmin1! 2>/dev/null || true
        echo "Ingested: $logfile"
    fi
done

# Ingest Linux syslog data (Loghub)
find /opt/splunk_data/syslog -type f \( -name "*.log" -o -name "Linux*" -o -name "*.txt" \) | while read -r logfile; do
    /opt/splunk/bin/splunk add oneshot "$logfile" -index system_logs -sourcetype syslog -auth admin:SplunkAdmin1! 2>/dev/null || true
    echo "Ingested: $logfile"
done

# Ingest Apache logs (Loghub)
find /opt/splunk_data/apache -type f \( -name "*.log" -o -name "Apache*" -o -name "*.txt" \) | while read -r logfile; do
    /opt/splunk/bin/splunk add oneshot "$logfile" -index web_logs -sourcetype apache_error -auth admin:SplunkAdmin1! 2>/dev/null || true
    echo "Ingested: $logfile"
done

# Also monitor the VM's own live system logs
/opt/splunk/bin/splunk add monitor /var/log/syslog -index system_logs -sourcetype syslog -auth admin:SplunkAdmin1! 2>/dev/null || true
/opt/splunk/bin/splunk add monitor /var/log/auth.log -index security_logs -sourcetype linux_secure -auth admin:SplunkAdmin1! 2>/dev/null || true

# Wait for indexing to process
echo "=== Waiting for data indexing ==="
sleep 15

# Verify data was ingested
echo "=== Verifying data ingestion ==="
EVENT_COUNT=$(curl -sk -u admin:SplunkAdmin1! \
    "https://localhost:8089/services/search/jobs" \
    -d search="search index=* | stats count" \
    -d exec_mode=oneshot \
    -d output_mode=json 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    results = data.get('results', [])
    if results:
        print(results[0].get('count', '0'))
    else:
        print('0')
except:
    print('unknown')
" 2>/dev/null || echo "unknown")
echo "Total events indexed: $EVENT_COUNT"

# Create a saved search for demo
curl -sk -u admin:SplunkAdmin1! \
    "https://localhost:8089/servicesNS/admin/search/saved/searches" \
    -d name="Failed_SSH_Logins" \
    -d search="index=security_logs (\"Failed password\" OR \"authentication failure\") | stats count by src_ip, user" \
    -d description="Summary of failed SSH login attempts by source IP and user" \
    -d is_visible=1 \
    2>/dev/null || true

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
user_pref("browser.startup.homepage", "http://localhost:8000");
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
cat > /home/ga/Desktop/Splunk.desktop << 'DESKTOP'
[Desktop Entry]
Name=Splunk Enterprise
Comment=Open Splunk Enterprise Web Interface
Exec=firefox http://localhost:8000/
Icon=firefox
Type=Application
Categories=Network;Security;
DESKTOP
chmod +x /home/ga/Desktop/Splunk.desktop
chown ga:ga /home/ga/Desktop/Splunk.desktop

# Launch Firefox with Splunk URL
su - ga -c "DISPLAY=:1 firefox 'http://localhost:8000/' > /tmp/firefox.log 2>&1 &"

# Wait for Firefox window
echo "=== Waiting for Firefox ==="
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|splunk\|mozilla"; then
        echo "Firefox detected"
        break
    fi
    sleep 1
done

# Get and maximize Firefox window
sleep 3
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|splunk\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    echo "Firefox maximized: $WID"
fi

echo "=== Splunk Enterprise setup complete ==="
echo "Web UI: http://localhost:8000"
echo "REST API: https://localhost:8089"
echo "Credentials: admin / SplunkAdmin1!"
