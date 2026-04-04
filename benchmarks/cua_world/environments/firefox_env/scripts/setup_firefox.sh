#!/bin/bash
# setup_firefox.sh - Post-start hook for Firefox environment
# Configures Firefox profile and user settings
set -e

echo "=== Setting up Firefox Environment ==="

# Function to setup Firefox for a user
setup_user_firefox() {
    local username=$1
    local home_dir=$2

    echo "Setting up Firefox for user: $username"

    # Create Firefox profile directory structure
    local profile_dir="$home_dir/.mozilla/firefox"
    sudo -u "$username" mkdir -p "$profile_dir/default.profile"

    # Create profiles.ini to use our custom profile
    cat > "$profile_dir/profiles.ini" << 'EOF'
[Install4F96D1932A9F858E]
Default=default.profile
Locked=1

[Profile0]
Name=default
IsRelative=1
Path=default.profile
Default=1
EOF
    chown "$username:$username" "$profile_dir/profiles.ini"

    # Create installs.ini
    cat > "$profile_dir/installs.ini" << 'EOF'
[4F96D1932A9F858E]
Default=default.profile
Locked=1
EOF
    chown "$username:$username" "$profile_dir/installs.ini"

    # Create user.js with preferences to disable first-run and popups
    cat > "$profile_dir/default.profile/user.js" << 'EOF'
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

// Privacy and telemetry settings
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("browser.discovery.enabled", false);
user_pref("app.shield.optoutstudies.enabled", false);

// Disable pocket
user_pref("extensions.pocket.enabled", false);

// Accept all cookies (useful for testing)
user_pref("network.cookie.cookieBehavior", 0);

// Disable password saving prompts
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);

// Disable form autofill
user_pref("browser.formfill.enable", false);
user_pref("extensions.formautofill.addresses.enabled", false);
user_pref("extensions.formautofill.creditCards.enabled", false);

// Set homepage to blank
user_pref("browser.startup.homepage", "about:blank");
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.startup.page", 0);

// Disable safe browsing (for faster page loads in testing)
user_pref("browser.safebrowsing.enabled", false);
user_pref("browser.safebrowsing.malware.enabled", false);
user_pref("browser.safebrowsing.phishing.enabled", false);

// Performance settings
user_pref("browser.cache.disk.enable", true);
user_pref("browser.cache.memory.enable", true);

// Enable remote debugging (useful for automation)
user_pref("devtools.debugger.remote-enabled", true);
user_pref("devtools.chrome.enabled", true);
user_pref("devtools.debugger.prompt-connection", false);

// Allow about:config access without warning
user_pref("browser.aboutConfig.showWarning", false);

// Download settings
user_pref("browser.download.folderList", 2);
user_pref("browser.download.dir", "/home/ga/Downloads");
user_pref("browser.download.useDownloadDir", true);
user_pref("browser.download.manager.showWhenStarting", false);
user_pref("browser.helperApps.neverAsk.saveToDisk", "application/pdf,application/zip,application/octet-stream,text/plain,text/csv,application/json");
EOF
    chown "$username:$username" "$profile_dir/default.profile/user.js"

    # Create Downloads and Documents directories
    sudo -u "$username" mkdir -p "$home_dir/Downloads"
    sudo -u "$username" mkdir -p "$home_dir/Documents"

    # Create desktop shortcut
    sudo -u "$username" mkdir -p "$home_dir/Desktop"
    cat > "$home_dir/Desktop/Firefox.desktop" << 'DESKTOPEOF'
[Desktop Entry]
Name=Firefox Web Browser
Comment=Browse the World Wide Web
GenericName=Web Browser
Keywords=Internet;WWW;Browser;Web;Explorer
Exec=firefox %u
Terminal=false
X-MultipleArgs=false
Type=Application
Icon=firefox
Categories=GNOME;GTK;Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;application/xml;application/rss+xml;application/rdf+xml;image/gif;image/jpeg;image/png;x-scheme-handler/http;x-scheme-handler/https;x-scheme-handler/ftp;
StartupNotify=true
DESKTOPEOF
    chmod +x "$home_dir/Desktop/Firefox.desktop"
    chown "$username:$username" "$home_dir/Desktop/Firefox.desktop"

    # Make the .desktop file trusted (GNOME)
    sudo -u "$username" gio set "$home_dir/Desktop/Firefox.desktop" metadata::trusted yes 2>/dev/null || true

    # Create Firefox launch script
    cat > "$home_dir/launch_firefox.sh" << 'LAUNCHEOF'
#!/bin/bash
# Launch Firefox with custom profile
export DISPLAY=${DISPLAY:-:1}
xhost +local: 2>/dev/null || true

# Launch Firefox with profile
firefox -P default --no-remote "$@" > /tmp/firefox_launch.log 2>&1 &
FIREFOX_PID=$!
echo "Firefox launched with PID: $FIREFOX_PID"
LAUNCHEOF
    chmod +x "$home_dir/launch_firefox.sh"
    chown "$username:$username" "$home_dir/launch_firefox.sh"

    # Fix ownership
    chown -R "$username:$username" "$profile_dir"

    echo "Firefox setup complete for $username"
}

# Wait for desktop to be ready
echo "Waiting for desktop to be ready..."
sleep 5

# Setup Firefox for the ga user
if id "ga" &>/dev/null; then
    setup_user_firefox "ga" "/home/ga"
fi

# Create Firefox utility script
cat > /usr/local/bin/firefox-util << 'UTILEOF'
#!/bin/bash
# Firefox utility script for querying browser state

PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"
PLACES_DB="$PROFILE_DIR/places.sqlite"

case "$1" in
    bookmarks)
        # List all bookmarks
        if [ -f "$PLACES_DB" ]; then
            sqlite3 "$PLACES_DB" "SELECT b.title, p.url FROM moz_bookmarks b JOIN moz_places p ON b.fk = p.id WHERE b.type = 1 AND p.url NOT LIKE 'place:%';"
        else
            echo "No places.sqlite found"
        fi
        ;;
    history)
        # Show recent history
        if [ -f "$PLACES_DB" ]; then
            sqlite3 "$PLACES_DB" "SELECT p.url, p.title, datetime(h.visit_date/1000000, 'unixepoch') as visit_time FROM moz_places p JOIN moz_historyvisits h ON p.id = h.place_id ORDER BY h.visit_date DESC LIMIT ${2:-10};"
        else
            echo "No places.sqlite found"
        fi
        ;;
    downloads)
        # Show recent downloads
        if [ -f "$PLACES_DB" ]; then
            sqlite3 "$PLACES_DB" "SELECT a.content as file, datetime(a.dateAdded/1000000, 'unixepoch') as download_time FROM moz_annos a WHERE a.anno_attribute_id = (SELECT id FROM moz_anno_attributes WHERE name = 'downloads/destinationFileName') ORDER BY a.dateAdded DESC LIMIT ${2:-10};"
        else
            echo "No places.sqlite found"
        fi
        ;;
    profile)
        # Show profile path
        echo "$PROFILE_DIR"
        ;;
    cookies)
        # Show cookies count
        COOKIES_DB="$PROFILE_DIR/cookies.sqlite"
        if [ -f "$COOKIES_DB" ]; then
            sqlite3 "$COOKIES_DB" "SELECT COUNT(*) as count FROM moz_cookies;"
        else
            echo "No cookies.sqlite found"
        fi
        ;;
    *)
        echo "Usage: firefox-util {bookmarks|history [n]|downloads [n]|profile|cookies}"
        echo "  bookmarks  - List all bookmarks"
        echo "  history    - Show recent history (default: 10, specify n for more)"
        echo "  downloads  - Show recent downloads (default: 10, specify n for more)"
        echo "  profile    - Show profile directory path"
        echo "  cookies    - Show cookie count"
        ;;
esac
UTILEOF
chmod +x /usr/local/bin/firefox-util

# Create task utilities script
mkdir -p /workspace/utils 2>/dev/null || true
cat > /workspace/utils/task_utils.sh << 'TASKUTILSEOF'
#!/bin/bash
# Shared utility functions for Firefox tasks

# Kill Firefox for a user
kill_firefox() {
    local username=${1:-ga}
    echo "Killing Firefox for user: $username"
    pkill -u "$username" -f firefox 2>/dev/null || true
    sleep 2
    pkill -9 -u "$username" -f firefox 2>/dev/null || true
    sleep 1
}

# Wait for a process to start
wait_for_process() {
    local process_name=$1
    local timeout=${2:-30}
    local elapsed=0

    echo "Waiting for $process_name process (timeout: ${timeout}s)..."
    while [ $elapsed -lt $timeout ]; do
        if pgrep -f "$process_name" > /dev/null; then
            echo "$process_name process found after ${elapsed}s"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "Timeout waiting for $process_name process"
    return 1
}

# Wait for a window to appear
wait_for_window() {
    local window_name=$1
    local timeout=${2:-30}
    local elapsed=0

    echo "Waiting for window matching '$window_name' (timeout: ${timeout}s)..."
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "$window_name"; then
            echo "Window found after ${elapsed}s"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "Timeout waiting for window '$window_name'"
    return 1
}

# Get Firefox window ID
get_firefox_window_id() {
    DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}'
}

# Focus a window by ID
focus_window() {
    local window_id=$1
    if [ -n "$window_id" ]; then
        DISPLAY=:1 wmctrl -i -a "$window_id" 2>/dev/null
        sleep 0.5
    fi
}

# Take screenshot
take_screenshot() {
    local output_path=${1:-/tmp/screenshot.png}
    DISPLAY=:1 scrot "$output_path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$output_path" 2>/dev/null || true
}

# Get Firefox profile path
get_profile_path() {
    local username=${1:-ga}
    echo "/home/$username/.mozilla/firefox/default.profile"
}

# Check if places.sqlite exists and is accessible
check_places_db() {
    local username=${1:-ga}
    local places_db="/home/$username/.mozilla/firefox/default.profile/places.sqlite"
    if [ -f "$places_db" ]; then
        echo "$places_db"
        return 0
    else
        echo ""
        return 1
    fi
}

# Query Firefox database (handles lock issues)
query_firefox_db() {
    local db_path=$1
    local query=$2

    if [ ! -f "$db_path" ]; then
        echo ""
        return 1
    fi

    # Try direct query first, then copy if locked
    local result
    result=$(sqlite3 "$db_path" "$query" 2>/dev/null)
    if [ $? -ne 0 ]; then
        # Database might be locked, create a copy
        local temp_db="/tmp/firefox_db_copy_$$.sqlite"
        cp "$db_path" "$temp_db" 2>/dev/null
        result=$(sqlite3 "$temp_db" "$query" 2>/dev/null)
        rm -f "$temp_db"
    fi
    echo "$result"
}
TASKUTILSEOF
chmod +x /workspace/utils/task_utils.sh 2>/dev/null || true

echo "=== Firefox Environment Setup Complete ==="
echo "Firefox profile: /home/ga/.mozilla/firefox/default.profile"
echo "Launch script: /home/ga/launch_firefox.sh"
echo "Utility: /usr/local/bin/firefox-util"
