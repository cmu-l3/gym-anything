#!/bin/bash
# Jenkins Setup Script (post_start hook)
# Starts Jenkins via Docker and launches Firefox

echo "=== Setting up Jenkins via Docker ==="

# Configuration
JENKINS_URL="http://localhost:8080"
ADMIN_USER="admin"
ADMIN_PASS="Admin123!"

# Function to wait for Jenkins to be ready
wait_for_jenkins() {
    local timeout=${1:-240}
    local elapsed=0

    echo "Waiting for Jenkins to be ready (this may take a few minutes on first run)..."

    while [ $elapsed -lt $timeout ]; do
        # Check if Jenkins returns HTTP 200 or 403 (403 means it's up but needs auth)
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$JENKINS_URL" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "403" ]; then
            echo "Jenkins is ready after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "  Waiting... ${elapsed}s (HTTP $HTTP_CODE)"
    done

    echo "WARNING: Jenkins readiness check timed out after ${timeout}s"
    return 1
}

# Copy docker-compose.yml to working directory
echo "Setting up Docker Compose configuration..."
mkdir -p /home/ga/jenkins
cp /workspace/config/docker-compose.yml /home/ga/jenkins/
chown -R ga:ga /home/ga/jenkins

# Create jenkins_home directory with init.groovy.d for auto-configuration
echo "Setting up Jenkins auto-configuration..."
mkdir -p /home/ga/jenkins/jenkins_home/init.groovy.d
cp /workspace/config/init-jenkins.groovy /home/ga/jenkins/jenkins_home/init.groovy.d/
chmod 755 /home/ga/jenkins/jenkins_home/init.groovy.d/init-jenkins.groovy
chown -R 1000:1000 /home/ga/jenkins/jenkins_home

# Start Jenkins containers
echo "Starting Jenkins Docker containers..."
cd /home/ga/jenkins

# Pull images first (better error handling)
docker-compose pull

# Start containers in detached mode
docker-compose up -d

echo "Containers starting..."
docker-compose ps

# Wait for Jenkins to be fully ready
wait_for_jenkins 240

# Show container status
echo ""
echo "Container status:"
docker-compose ps

# Wait for init.groovy to execute, then verify admin credentials with retry
echo ""
echo "Verifying Jenkins setup with admin credentials..."
ADMIN_VERIFIED=false
for attempt in $(seq 1 12); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$ADMIN_USER:$ADMIN_PASS" "$JENKINS_URL/api/json" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        echo "Jenkins API is accessible with admin credentials (attempt $attempt)"
        ADMIN_VERIFIED=true
        break
    fi
    echo "  Admin auth attempt $attempt: HTTP $HTTP_CODE, retrying in 5s..."
    sleep 5
done

if [ "$ADMIN_VERIFIED" = "false" ]; then
    echo "WARNING: Admin credentials not verified after 60s. Groovy init may still be running."
fi

# Install required plugins (Pipeline, Git, etc.)
echo "Installing required Jenkins plugins..."
# Download CLI jar
curl -s "$JENKINS_URL/jnlpJars/jenkins-cli.jar" -o /tmp/jenkins-cli.jar 2>/dev/null || true

if [ -f /tmp/jenkins-cli.jar ]; then
    # Install plugins via CLI
    for PLUGIN in workflow-aggregator git credentials pipeline-stage-view pipeline-stage-step pipeline-graph-analysis; do
        echo "  Installing plugin: $PLUGIN..."
        java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$ADMIN_USER:$ADMIN_PASS" install-plugin "$PLUGIN" 2>/dev/null || echo "  WARNING: Failed to install $PLUGIN"
    done

    # Restart Jenkins to load plugins (safe-restart)
    echo "Restarting Jenkins to load plugins..."
    java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$ADMIN_USER:$ADMIN_PASS" safe-restart 2>/dev/null || true

    # Wait for Jenkins to restart
    sleep 10
    wait_for_jenkins 120
    sleep 5
else
    echo "WARNING: Could not download jenkins-cli.jar, plugins not installed"
fi

# Set up Firefox profile for user 'ga'
# Detect if Firefox is a Snap install (Ubuntu 22.04+ default)
echo "Setting up Firefox profile..."
IS_SNAP_FIREFOX=false
if snap list firefox 2>/dev/null | grep -q firefox; then
    IS_SNAP_FIREFOX=true
    echo "Detected Snap Firefox installation"
fi

# Configure user.js content (shared between Snap and non-Snap)
FIREFOX_USERJS='// Disable first-run screens and welcome pages
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);

// Set homepage to Jenkins
user_pref("browser.startup.homepage", "http://localhost:8080");
user_pref("browser.startup.page", 1);

// Disable update checks
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);

// Disable password saving prompts
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);

// Disable sidebar and other popups
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
user_pref("sidebar.main.tools", "");
user_pref("sidebar.nimbus", "");
user_pref("browser.sidebar.dismissed", true);
user_pref("browser.vpn_promo.enabled", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("browser.uitour.enabled", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
'

PROFILES_INI='[Install4F96D1932A9F858E]
Default=default-release
Locked=1

[Profile0]
Name=default-release
IsRelative=1
Path=default-release
Default=1

[General]
StartWithLastProfile=1
Version=2
'

# Write profile to standard location
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox"
sudo -u ga mkdir -p "$FIREFOX_PROFILE_DIR/default-release"
echo "$PROFILES_INI" > "$FIREFOX_PROFILE_DIR/profiles.ini"
chown ga:ga "$FIREFOX_PROFILE_DIR/profiles.ini"
echo "$FIREFOX_USERJS" > "$FIREFOX_PROFILE_DIR/default-release/user.js"
chown ga:ga "$FIREFOX_PROFILE_DIR/default-release/user.js"
chown -R ga:ga "$FIREFOX_PROFILE_DIR"

# If Snap Firefox, also write profile to Snap location
# Snap Firefox uses a different profile directory
if [ "$IS_SNAP_FIREFOX" = "true" ]; then
    echo "Configuring Snap Firefox profile..."
    # Launch Firefox briefly to create Snap profile structure, then kill it
    su - ga -c "DISPLAY=:1 firefox --headless &" 2>/dev/null || true
    sleep 5
    pkill -f "firefox" 2>/dev/null || true
    sleep 2

    SNAP_PROFILE_DIR="/home/ga/snap/firefox/common/.mozilla/firefox"
    if [ -d "$SNAP_PROFILE_DIR" ]; then
        # Find the default profile directory in the Snap path
        SNAP_PROFILE=$(find "$SNAP_PROFILE_DIR" -maxdepth 1 -name "*.default-release" -type d | head -1)
        if [ -z "$SNAP_PROFILE" ]; then
            SNAP_PROFILE="$SNAP_PROFILE_DIR/default-release"
            sudo -u ga mkdir -p "$SNAP_PROFILE"
        fi
        echo "$FIREFOX_USERJS" > "$SNAP_PROFILE/user.js"
        chown ga:ga "$SNAP_PROFILE/user.js"
        echo "Snap Firefox profile configured at: $SNAP_PROFILE"
    else
        # Create the directory structure
        sudo -u ga mkdir -p "$SNAP_PROFILE_DIR/default-release"
        echo "$PROFILES_INI" > "$SNAP_PROFILE_DIR/profiles.ini"
        echo "$FIREFOX_USERJS" > "$SNAP_PROFILE_DIR/default-release/user.js"
        chown -R ga:ga "/home/ga/snap/firefox"
        echo "Snap Firefox profile created at: $SNAP_PROFILE_DIR"
    fi
fi

# Create desktop shortcut
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/Jenkins.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=Jenkins
Comment=CI/CD Automation Server
Exec=firefox http://localhost:8080
Icon=applications-development
StartupNotify=true
Terminal=false
Type=Application
Categories=Development;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/Jenkins.desktop
chmod +x /home/ga/Desktop/Jenkins.desktop

# Create utility script for Jenkins CLI operations
cat > /usr/local/bin/jenkins-cli << 'JCLISCRIPT'
#!/bin/bash
# Execute Jenkins CLI commands
JENKINS_URL="http://localhost:8080"
JENKINS_USER="admin"
JENKINS_PASS="Admin123!"

# Download CLI jar if not exists
if [ ! -f /tmp/jenkins-cli.jar ]; then
    curl -s "$JENKINS_URL/jnlpJars/jenkins-cli.jar" -o /tmp/jenkins-cli.jar
fi

# Execute CLI command
java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" "$@"
JCLISCRIPT
chmod +x /usr/local/bin/jenkins-cli

# Create utility script for API queries
cat > /usr/local/bin/jenkins-api << 'APISCRIPT'
#!/bin/bash
# Query Jenkins REST API
JENKINS_URL="http://localhost:8080"
JENKINS_USER="admin"
JENKINS_PASS="Admin123!"

curl -s -u "$JENKINS_USER:$JENKINS_PASS" "$JENKINS_URL/$1"
APISCRIPT
chmod +x /usr/local/bin/jenkins-api

# Start Firefox for the ga user
echo "Launching Firefox with Jenkins..."
su - ga -c "DISPLAY=:1 firefox '$JENKINS_URL' > /tmp/firefox_jenkins.log 2>&1 &"

# Wait for Firefox window
sleep 5
FIREFOX_STARTED=false
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|jenkins"; then
        FIREFOX_STARTED=true
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$FIREFOX_STARTED" = true ]; then
    sleep 2
    # Maximize Firefox window
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

echo ""
echo "=== Jenkins Setup Complete ==="
echo ""
echo "Jenkins is running at: http://localhost:8080"
echo ""
echo "Login Credentials:"
echo "  Username: ${ADMIN_USER}"
echo "  Password: ${ADMIN_PASS}"
echo ""
echo "CLI commands:"
echo "  jenkins-cli list-jobs"
echo "  jenkins-cli create-job <job-name> < config.xml"
echo "  jenkins-cli build <job-name>"
echo ""
echo "API commands:"
echo "  jenkins-api 'api/json?pretty=true'"
echo "  jenkins-api 'job/<job-name>/api/json'"
echo ""
echo "Docker commands:"
echo "  docker-compose -f /home/ga/jenkins/docker-compose.yml logs -f"
echo "  docker-compose -f /home/ga/jenkins/docker-compose.yml ps"
echo ""
