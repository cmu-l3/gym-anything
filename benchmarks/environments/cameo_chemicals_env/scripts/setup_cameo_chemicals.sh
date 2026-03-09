#!/bin/bash
# setup_cameo_chemicals.sh - Post-start hook for CAMEO Chemicals environment
# Configures Firefox profile and opens CAMEO Chemicals website
set -e

echo "=== Setting up CAMEO Chemicals Environment ==="

# Wait for desktop to be ready
echo "Waiting for desktop to be ready..."
sleep 5

USERNAME="ga"
HOME_DIR="/home/ga"

# Create Firefox profile directory structure
PROFILE_DIR="$HOME_DIR/.mozilla/firefox"
sudo -u "$USERNAME" mkdir -p "$PROFILE_DIR/default.profile"

# Create profiles.ini
cat > "$PROFILE_DIR/profiles.ini" << 'EOF'
[Install4F96D1932A9F858E]
Default=default.profile
Locked=1

[Profile0]
Name=default
IsRelative=1
Path=default.profile
Default=1
EOF
chown "$USERNAME:$USERNAME" "$PROFILE_DIR/profiles.ini"

# Create installs.ini
cat > "$PROFILE_DIR/installs.ini" << 'EOF'
[4F96D1932A9F858E]
Default=default.profile
Locked=1
EOF
chown "$USERNAME:$USERNAME" "$PROFILE_DIR/installs.ini"

# Create user.js with preferences to disable first-run and popups
cat > "$PROFILE_DIR/default.profile/user.js" << 'EOF'
// Disable first-run screens and updates
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("browser.startup.firstrunSkipsHomepage", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("trailhead.firstrun.didSeeAboutWelcome", true);

// Disable updates
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("app.update.checkInstallTime", false);

// Disable various popups and prompts
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.tabs.warnOnCloseOtherTabs", false);
user_pref("browser.tabs.warnOnOpen", false);
user_pref("browser.warnOnQuit", false);
user_pref("browser.warnOnQuitShortcut", false);
user_pref("security.warn_entering_secure", false);
user_pref("security.warn_leaving_secure", false);
user_pref("security.warn_submit_insecure", false);

// Privacy and telemetry
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("browser.discovery.enabled", false);
user_pref("app.shield.optoutstudies.enabled", false);

// Disable pocket
user_pref("extensions.pocket.enabled", false);

// Accept all cookies
user_pref("network.cookie.cookieBehavior", 0);

// Disable password saving prompts
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);

// Disable form autofill
user_pref("browser.formfill.enable", false);
user_pref("extensions.formautofill.addresses.enabled", false);
user_pref("extensions.formautofill.creditCards.enabled", false);

// Set homepage to CAMEO Chemicals
user_pref("browser.startup.homepage", "https://cameochemicals.noaa.gov/");
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.startup.page", 1);

// Disable safe browsing for faster page loads
user_pref("browser.safebrowsing.enabled", false);
user_pref("browser.safebrowsing.malware.enabled", false);
user_pref("browser.safebrowsing.phishing.enabled", false);

// Performance settings
user_pref("browser.cache.disk.enable", true);
user_pref("browser.cache.memory.enable", true);

// Allow about:config without warning
user_pref("browser.aboutConfig.showWarning", false);

// Download settings
user_pref("browser.download.folderList", 2);
user_pref("browser.download.dir", "/home/ga/Downloads");
user_pref("browser.download.useDownloadDir", true);
user_pref("browser.download.manager.showWhenStarting", false);
user_pref("browser.helperApps.neverAsk.saveToDisk", "application/pdf,application/zip,application/octet-stream,text/plain,text/csv,application/json");
EOF
chown "$USERNAME:$USERNAME" "$PROFILE_DIR/default.profile/user.js"

# Create required directories
sudo -u "$USERNAME" mkdir -p "$HOME_DIR/Downloads"
sudo -u "$USERNAME" mkdir -p "$HOME_DIR/Documents"
sudo -u "$USERNAME" mkdir -p "$HOME_DIR/Desktop"

# Copy scenario data files to Desktop for agent access
if [ -d "/workspace/data" ]; then
    cp /workspace/data/*.csv "$HOME_DIR/Desktop/" 2>/dev/null || true
    cp /workspace/data/*.txt "$HOME_DIR/Desktop/" 2>/dev/null || true
    chown -R "$USERNAME:$USERNAME" "$HOME_DIR/Desktop/"
fi

# Fix ownership
chown -R "$USERNAME:$USERNAME" "$PROFILE_DIR"

# Warm-up launch: start Firefox to initialize profile, then kill it
echo "Performing warm-up Firefox launch..."
su - "$USERNAME" -c "DISPLAY=:1 firefox -P default --no-remote https://cameochemicals.noaa.gov/ > /tmp/firefox_warmup.log 2>&1 &"

# Wait for Firefox process to start
TIMEOUT=30
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if pgrep -u "$USERNAME" -f firefox > /dev/null; then
        echo "Firefox warm-up started after ${ELAPSED}s"
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# Wait for window to appear
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla|CAMEO"; then
        echo "Firefox window appeared after ${ELAPSED}s"
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# Let Firefox fully initialize and load the page
sleep 5

# Kill Firefox to clear first-run state
echo "Killing warm-up Firefox..."
pkill -u "$USERNAME" -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u "$USERNAME" -f firefox 2>/dev/null || true
sleep 1

echo "=== CAMEO Chemicals Environment Setup Complete ==="
echo "Firefox profile configured at: $PROFILE_DIR/default.profile"
echo "Homepage set to: https://cameochemicals.noaa.gov/"
