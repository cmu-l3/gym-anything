#!/bin/bash
# setup_tor_browser.sh - Post-start hook for Tor Browser environment
# Configures Tor Browser profile and downloads the browser bundle
set -e

echo "=== Setting up Tor Browser Environment ==="

# Function to setup Tor Browser for a user
setup_user_tor_browser() {
    local username=$1
    local home_dir=$2

    echo "Setting up Tor Browser for user: $username"

    # Create required directories
    sudo -u "$username" mkdir -p "$home_dir/.local/share/torbrowser"
    sudo -u "$username" mkdir -p "$home_dir/.config/torbrowser"
    sudo -u "$username" mkdir -p "$home_dir/Downloads"
    sudo -u "$username" mkdir -p "$home_dir/Documents"
    sudo -u "$username" mkdir -p "$home_dir/Desktop"

    # Run torbrowser-launcher to download and set up Tor Browser
    # This downloads the official Tor Browser bundle and verifies its signature
    echo "Downloading Tor Browser bundle (this may take a few minutes)..."

    # Set up environment for torbrowser-launcher
    export DISPLAY=:1

    # Run torbrowser-launcher in download-only mode to get the bundle
    # The launcher handles GPG verification automatically
    sudo -u "$username" -H bash -c "
        export DISPLAY=:1
        export HOME=$home_dir
        # First run downloads and installs Tor Browser
        timeout 300 torbrowser-launcher --settings 2>/dev/null || true
    " || true

    # Wait for potential download
    sleep 5

    # Check for Tor Browser installation locations
    TOR_BROWSER_DIR=""
    for candidate in \
        "$home_dir/.local/share/torbrowser/tbb/x86_64/tor-browser" \
        "$home_dir/.local/share/torbrowser/tbb/aarch64/tor-browser" \
        "$home_dir/.local/share/torbrowser/tbb/tor-browser" \
        "/opt/tor-browser"
    do
        if [ -d "$candidate" ]; then
            TOR_BROWSER_DIR="$candidate"
            echo "Found Tor Browser at: $TOR_BROWSER_DIR"
            break
        fi
    done

    if [ -z "$TOR_BROWSER_DIR" ] || [ ! -d "$TOR_BROWSER_DIR/Browser" ]; then
        echo "Tor Browser not found. Attempting manual download..."

        # Fallback: Manual download from torproject.org
        # This handles cases where torbrowser-launcher's URLs are outdated
        ARCH=$(uname -m)
        if [ "$ARCH" = "x86_64" ]; then
            TOR_ARCH="x86_64"
        elif [ "$ARCH" = "aarch64" ]; then
            TOR_ARCH="aarch64"
        else
            echo "Unsupported architecture: $ARCH"
            return 1
        fi

        # Get the latest version from torproject.org
        echo "Fetching latest Tor Browser version..."
        TOR_VERSION=$(curl -sL "https://www.torproject.org/download/" 2>/dev/null | grep -oP "tor-browser-linux-${TOR_ARCH}-\K[0-9]+\.[0-9]+\.[0-9]+" | head -1)

        if [ -z "$TOR_VERSION" ]; then
            # Fallback to a known recent version
            TOR_VERSION="15.0.5"
            echo "Could not detect version, using fallback: $TOR_VERSION"
        else
            echo "Detected latest version: $TOR_VERSION"
        fi

        # Download Tor Browser
        TOR_URL="https://www.torproject.org/dist/torbrowser/${TOR_VERSION}/tor-browser-linux-${TOR_ARCH}-${TOR_VERSION}.tar.xz"
        echo "Downloading Tor Browser from: $TOR_URL"

        sudo -u "$username" mkdir -p "$home_dir/.local/share/torbrowser/tbb/${TOR_ARCH}"
        cd /tmp
        if curl -L -o tor-browser.tar.xz "$TOR_URL" 2>&1; then
            echo "Download successful, extracting..."
            tar -xf tor-browser.tar.xz

            # Move to the expected location
            rm -rf "$home_dir/.local/share/torbrowser/tbb/${TOR_ARCH}/tor-browser" 2>/dev/null || true
            mv tor-browser "$home_dir/.local/share/torbrowser/tbb/${TOR_ARCH}/"
            chown -R "$username:$username" "$home_dir/.local/share/torbrowser"

            rm -f tor-browser.tar.xz

            TOR_BROWSER_DIR="$home_dir/.local/share/torbrowser/tbb/${TOR_ARCH}/tor-browser"
            echo "Tor Browser installed manually at: $TOR_BROWSER_DIR"
        else
            echo "WARNING: Failed to download Tor Browser. Will try on first launch."
            TOR_BROWSER_DIR="$home_dir/.local/share/torbrowser/tbb/x86_64/tor-browser"
        fi
    fi

    # Create Tor Browser profile configuration to skip first-run wizard
    # The profile is located within the Tor Browser directory
    TOR_BROWSER_PROFILE_DIR="$TOR_BROWSER_DIR/Browser/TorBrowser/Data/Browser/profile.default"
    if [ -d "$TOR_BROWSER_PROFILE_DIR" ]; then
        echo "Configuring Tor Browser profile..."

        # Create user.js to disable first-run screens and configure preferences
        cat > "$TOR_BROWSER_PROFILE_DIR/user.js" << 'EOF'
// Disable first-run screens and updates
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.rights.3.shown", true);
user_pref("browser.startup.firstrunSkipsHomepage", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);

// Skip Tor welcome pages
user_pref("extensions.torlauncher.prompt_at_startup", false);
user_pref("extensions.torlauncher.quickstart", true);
user_pref("torbrowser.settings.quickstart.enabled", true);

// Disable updates (for stable testing environment)
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("app.update.checkInstallTime", false);

// Disable various popups and prompts
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.tabs.warnOnCloseOtherTabs", false);
user_pref("browser.tabs.warnOnOpen", false);
user_pref("browser.warnOnQuit", false);
user_pref("browser.warnOnQuitShortcut", false);

// Allow about:config access without warning
user_pref("browser.aboutConfig.showWarning", false);

// Download settings
user_pref("browser.download.folderList", 2);
user_pref("browser.download.useDownloadDir", true);
user_pref("browser.download.manager.showWhenStarting", false);

// Enable remote debugging (useful for automation)
user_pref("devtools.debugger.remote-enabled", true);
user_pref("devtools.chrome.enabled", true);
user_pref("devtools.debugger.prompt-connection", false);
EOF
        chown "$username:$username" "$TOR_BROWSER_PROFILE_DIR/user.js"
        echo "Profile configured"
    else
        echo "Profile directory not found yet - will be created on first launch"
    fi

    # Create torbrowser-launcher settings to auto-connect
    mkdir -p "$home_dir/.config/torbrowser"
    cat > "$home_dir/.config/torbrowser/settings.json" << 'EOF'
{
    "installed": false,
    "download_over_tor": false,
    "modem_sound": false,
    "autoconnect": true
}
EOF
    chown -R "$username:$username" "$home_dir/.config/torbrowser"

    # Create desktop shortcut
    cat > "$home_dir/Desktop/TorBrowser.desktop" << 'DESKTOPEOF'
[Desktop Entry]
Name=Tor Browser
Comment=Browse the web anonymously
GenericName=Web Browser
Keywords=Internet;WWW;Browser;Web;Anonymous;Tor;Privacy
Exec=torbrowser-launcher %u
Terminal=false
X-MultipleArgs=false
Type=Application
Icon=torbrowser
Categories=Network;WebBrowser;Security;
MimeType=text/html;text/xml;application/xhtml+xml;application/xml;x-scheme-handler/http;x-scheme-handler/https;
StartupNotify=true
StartupWMClass=Tor Browser
DESKTOPEOF
    chmod +x "$home_dir/Desktop/TorBrowser.desktop"
    chown "$username:$username" "$home_dir/Desktop/TorBrowser.desktop"

    # Make the .desktop file trusted (GNOME)
    sudo -u "$username" gio set "$home_dir/Desktop/TorBrowser.desktop" metadata::trusted yes 2>/dev/null || true

    # Create Tor Browser launch script with environment setup
    cat > "$home_dir/launch_tor_browser.sh" << 'LAUNCHEOF'
#!/bin/bash
# Launch Tor Browser with proper environment
export DISPLAY=${DISPLAY:-:1}
xhost +local: 2>/dev/null || true

# Launch Tor Browser via torbrowser-launcher
torbrowser-launcher "$@" > /tmp/tor_browser_launch.log 2>&1 &
TOR_PID=$!
echo "Tor Browser launcher started with PID: $TOR_PID"
LAUNCHEOF
    chmod +x "$home_dir/launch_tor_browser.sh"
    chown "$username:$username" "$home_dir/launch_tor_browser.sh"

    # Fix ownership of all created directories
    chown -R "$username:$username" "$home_dir/.local" 2>/dev/null || true
    chown -R "$username:$username" "$home_dir/.config" 2>/dev/null || true

    echo "Tor Browser setup complete for $username"
}

# Wait for desktop to be ready
echo "Waiting for desktop to be ready..."
sleep 5

# Setup Tor Browser for the ga user
if id "ga" &>/dev/null; then
    setup_user_tor_browser "ga" "/home/ga"
fi

# Create Tor Browser utility script
cat > /usr/local/bin/tor-browser-util << 'UTILEOF'
#!/bin/bash
# Tor Browser utility script for querying browser state

# Find Tor Browser profile directory
find_profile_dir() {
    local home_dir="${1:-/home/ga}"
    for candidate in \
        "$home_dir/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
        "$home_dir/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
        "$home_dir/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Browser/profile.default"
    do
        if [ -d "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    echo ""
    return 1
}

PROFILE_DIR=$(find_profile_dir)
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
    profile)
        # Show profile path
        echo "$PROFILE_DIR"
        ;;
    status)
        # Check if Tor Browser is running
        if pgrep -f "tor-browser\|firefox.*TorBrowser" > /dev/null; then
            echo "Tor Browser is running"
            # Check if Tor circuit is established
            if pgrep -f "tor " > /dev/null; then
                echo "Tor daemon is running"
            else
                echo "Tor daemon is NOT running"
            fi
        else
            echo "Tor Browser is NOT running"
        fi
        ;;
    windows)
        # List Tor Browser windows
        DISPLAY=:1 wmctrl -l | grep -iE "tor browser|tor-browser"
        ;;
    *)
        echo "Usage: tor-browser-util {bookmarks|history [n]|profile|status|windows}"
        echo "  bookmarks  - List all bookmarks"
        echo "  history    - Show recent history (default: 10, specify n for more)"
        echo "  profile    - Show profile directory path"
        echo "  status     - Check if Tor Browser and Tor daemon are running"
        echo "  windows    - List Tor Browser windows"
        ;;
esac
UTILEOF
chmod +x /usr/local/bin/tor-browser-util

# Create task utilities script
mkdir -p /workspace/utils 2>/dev/null || true
cat > /workspace/utils/task_utils.sh << 'TASKUTILSEOF'
#!/bin/bash
# Shared utility functions for Tor Browser tasks

# Find Tor Browser profile directory
find_tor_profile() {
    local home_dir="${1:-/home/ga}"
    for candidate in \
        "$home_dir/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
        "$home_dir/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
        "$home_dir/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Browser/profile.default"
    do
        if [ -d "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    echo ""
    return 1
}

# Kill Tor Browser for a user
kill_tor_browser() {
    local username=${1:-ga}
    echo "Killing Tor Browser for user: $username"
    pkill -u "$username" -f "tor-browser" 2>/dev/null || true
    pkill -u "$username" -f "firefox.*TorBrowser" 2>/dev/null || true
    sleep 2
    pkill -9 -u "$username" -f "tor-browser" 2>/dev/null || true
    pkill -9 -u "$username" -f "firefox.*TorBrowser" 2>/dev/null || true
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
    local timeout=${2:-60}
    local elapsed=0

    echo "Waiting for window matching '$window_name' (timeout: ${timeout}s)..."
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "$window_name"; then
            echo "Window found after ${elapsed}s"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "Timeout waiting for window '$window_name'"
    return 1
}

# Get Tor Browser window ID
get_tor_browser_window_id() {
    DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}'
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

# Check if Tor circuit is established
check_tor_circuit() {
    # Check if Tor daemon is running
    if pgrep -f "tor " > /dev/null; then
        # Try to connect to Tor control port
        if echo "GETINFO status/circuit-established" | nc -q 1 localhost 9151 2>/dev/null | grep -q "250"; then
            echo "established"
            return 0
        fi
    fi
    echo "not_established"
    return 1
}

# Query Tor Browser database (handles lock issues)
query_tor_db() {
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
        local temp_db="/tmp/tor_db_copy_$$.sqlite"
        cp "$db_path" "$temp_db" 2>/dev/null
        result=$(sqlite3 "$temp_db" "$query" 2>/dev/null)
        rm -f "$temp_db"
    fi
    echo "$result"
}
TASKUTILSEOF
chmod +x /workspace/utils/task_utils.sh 2>/dev/null || true

echo "=== Tor Browser Environment Setup Complete ==="
echo "Tor Browser launcher: torbrowser-launcher"
echo "Launch script: /home/ga/launch_tor_browser.sh"
echo "Utility: /usr/local/bin/tor-browser-util"
