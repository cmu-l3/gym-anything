#!/bin/bash
# setup_edge.sh - Post-start hook for Microsoft Edge environment
# Configures Edge profile and user settings
set -e

echo "=== Setting up Microsoft Edge Environment ==="

# Function to setup Edge for a user
setup_user_edge() {
    local username=$1
    local home_dir=$2

    echo "Setting up Microsoft Edge for user: $username"

    # Create Edge config directory structure
    # Microsoft Edge on Linux uses ~/.config/microsoft-edge/
    local config_dir="$home_dir/.config/microsoft-edge"
    sudo -u "$username" mkdir -p "$config_dir/Default"

    # Create Local State file to disable first run
    cat > "$config_dir/Local State" << 'EOF'
{
  "browser": {
    "enabled_labs_experiments": [],
    "has_seen_welcome_page": true
  },
  "profile": {
    "info_cache": {}
  },
  "fre": {
    "has_user_seen_fre": true
  }
}
EOF
    chown "$username:$username" "$config_dir/Local State"

    # Create Preferences file to disable prompts and configure settings
    cat > "$config_dir/Default/Preferences" << 'EOF'
{
  "browser": {
    "check_default_browser": false,
    "show_home_button": true,
    "has_seen_welcome_page": true
  },
  "bookmark_bar": {
    "show_on_all_tabs": true
  },
  "distribution": {
    "suppress_first_run_default_browser_prompt": true,
    "skip_first_run_ui": true,
    "suppress_first_run_bubble": true,
    "make_chrome_default": false,
    "import_bookmarks": false,
    "import_history": false,
    "import_search_engine": false,
    "do_not_register_for_update_launch": true
  },
  "download": {
    "default_directory": "/home/ga/Downloads",
    "prompt_for_download": false
  },
  "profile": {
    "default_content_setting_values": {
      "notifications": 2
    },
    "password_manager_enabled": false,
    "name": "Default"
  },
  "autofill": {
    "enabled": false,
    "profile_enabled": false,
    "credit_card_enabled": false
  },
  "credentials_enable_service": false,
  "savefile": {
    "default_directory": "/home/ga/Downloads"
  },
  "session": {
    "restore_on_startup": 5
  },
  "homepage": "about:blank",
  "homepage_is_newtabpage": false,
  "sync_promo": {
    "show_on_first_run_allowed": false
  },
  "signin": {
    "allowed": false
  },
  "translate": {
    "enabled": false
  },
  "translate_blocked_languages": ["en"],
  "safebrowsing": {
    "enabled": false
  },
  "default_search_provider_data": {
    "template_url_data": {
      "keyword": "bing.com",
      "short_name": "Bing",
      "url": "https://www.bing.com/search?q={searchTerms}"
    }
  }
}
EOF
    chown "$username:$username" "$config_dir/Default/Preferences"

    # Create First Run file to skip first run experience
    touch "$config_dir/First Run"
    chown "$username:$username" "$config_dir/First Run"

    # Create Downloads and Documents directories
    sudo -u "$username" mkdir -p "$home_dir/Downloads"
    sudo -u "$username" mkdir -p "$home_dir/Documents"

    # Create desktop shortcut
    sudo -u "$username" mkdir -p "$home_dir/Desktop"
    cat > "$home_dir/Desktop/Microsoft-Edge.desktop" << 'DESKTOPEOF'
[Desktop Entry]
Name=Microsoft Edge
Comment=Access the Internet
GenericName=Web Browser
Keywords=Internet;WWW;Browser;Web;Explorer
Exec=microsoft-edge %u
Terminal=false
X-MultipleArgs=false
Type=Application
Icon=microsoft-edge
Categories=GNOME;GTK;Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;application/xml;application/rss+xml;application/rdf+xml;image/gif;image/jpeg;image/png;x-scheme-handler/http;x-scheme-handler/https;
StartupNotify=true
DESKTOPEOF
    chmod +x "$home_dir/Desktop/Microsoft-Edge.desktop"
    chown "$username:$username" "$home_dir/Desktop/Microsoft-Edge.desktop"

    # Make the .desktop file trusted (GNOME)
    sudo -u "$username" gio set "$home_dir/Desktop/Microsoft-Edge.desktop" metadata::trusted yes 2>/dev/null || true

    # Create Edge launch script with proper flags
    cat > "$home_dir/launch_edge.sh" << 'LAUNCHEOF'
#!/bin/bash
# Launch Microsoft Edge with custom profile
export DISPLAY=${DISPLAY:-:1}
xhost +local: 2>/dev/null || true

# Launch Edge with flags to disable first run and various prompts
microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --disable-extensions \
    --disable-component-update \
    --disable-background-networking \
    --disable-client-side-phishing-detection \
    --disable-default-apps \
    --disable-infobars \
    --password-store=basic \
    "$@" > /tmp/edge_launch.log 2>&1 &
EDGE_PID=$!
echo "Microsoft Edge launched with PID: $EDGE_PID"
LAUNCHEOF
    chmod +x "$home_dir/launch_edge.sh"
    chown "$username:$username" "$home_dir/launch_edge.sh"

    # Fix ownership of all config files
    chown -R "$username:$username" "$config_dir"

    echo "Microsoft Edge setup complete for $username"
}

# Wait for desktop to be ready
echo "Waiting for desktop to be ready..."
sleep 5

# Setup Edge for the ga user
if id "ga" &>/dev/null; then
    setup_user_edge "ga" "/home/ga"
fi

# Create Edge utility script
cat > /usr/local/bin/edge-util << 'UTILEOF'
#!/bin/bash
# Microsoft Edge utility script for querying browser state

CONFIG_DIR="/home/ga/.config/microsoft-edge/Default"
BOOKMARKS_FILE="$CONFIG_DIR/Bookmarks"
HISTORY_DB="$CONFIG_DIR/History"
COOKIES_DB="$CONFIG_DIR/Cookies"

case "$1" in
    bookmarks)
        # List all bookmarks from JSON file
        if [ -f "$BOOKMARKS_FILE" ]; then
            python3 -c "
import json
import sys

try:
    with open('$BOOKMARKS_FILE', 'r') as f:
        data = json.load(f)

    def extract_bookmarks(node, path=''):
        results = []
        if node.get('type') == 'url':
            results.append((path, node.get('name', ''), node.get('url', '')))
        elif node.get('type') == 'folder':
            new_path = path + '/' + node.get('name', '') if path else node.get('name', '')
            for child in node.get('children', []):
                results.extend(extract_bookmarks(child, new_path))
        return results

    roots = data.get('roots', {})
    all_bookmarks = []
    for root_name, root_node in roots.items():
        if isinstance(root_node, dict):
            all_bookmarks.extend(extract_bookmarks(root_node, root_name))

    for folder, name, url in all_bookmarks:
        if url and not url.startswith('chrome://'):
            print(f'{name}|{url}|{folder}')
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
"
        else
            echo "No Bookmarks file found"
        fi
        ;;
    history)
        # Show recent history
        if [ -f "$HISTORY_DB" ]; then
            # Copy to avoid lock issues
            cp "$HISTORY_DB" /tmp/history_copy.db 2>/dev/null
            sqlite3 /tmp/history_copy.db "SELECT url, title, datetime(last_visit_time/1000000-11644473600, 'unixepoch') as visit_time FROM urls ORDER BY last_visit_time DESC LIMIT ${2:-10};" 2>/dev/null
            rm -f /tmp/history_copy.db
        else
            echo "No History database found"
        fi
        ;;
    downloads)
        # Show recent downloads
        DOWNLOADS_DB="$CONFIG_DIR/History"
        if [ -f "$DOWNLOADS_DB" ]; then
            cp "$DOWNLOADS_DB" /tmp/downloads_copy.db 2>/dev/null
            sqlite3 /tmp/downloads_copy.db "SELECT target_path, tab_url, datetime(start_time/1000000-11644473600, 'unixepoch') as download_time FROM downloads ORDER BY start_time DESC LIMIT ${2:-10};" 2>/dev/null
            rm -f /tmp/downloads_copy.db
        else
            echo "No downloads database found"
        fi
        ;;
    profile)
        # Show profile path
        echo "$CONFIG_DIR"
        ;;
    cookies)
        # Show cookies count
        if [ -f "$COOKIES_DB" ]; then
            cp "$COOKIES_DB" /tmp/cookies_copy.db 2>/dev/null
            sqlite3 /tmp/cookies_copy.db "SELECT COUNT(*) as count FROM cookies;" 2>/dev/null
            rm -f /tmp/cookies_copy.db
        else
            echo "No Cookies database found"
        fi
        ;;
    *)
        echo "Usage: edge-util {bookmarks|history [n]|downloads [n]|profile|cookies}"
        echo "  bookmarks  - List all bookmarks"
        echo "  history    - Show recent history (default: 10, specify n for more)"
        echo "  downloads  - Show recent downloads (default: 10, specify n for more)"
        echo "  profile    - Show profile directory path"
        echo "  cookies    - Show cookie count"
        ;;
esac
UTILEOF
chmod +x /usr/local/bin/edge-util

# Create task utilities script
mkdir -p /workspace/utils 2>/dev/null || true
cat > /workspace/utils/task_utils.sh << 'TASKUTILSEOF'
#!/bin/bash
# Shared utility functions for Microsoft Edge tasks

# Kill Edge for a user
kill_edge() {
    local username=${1:-ga}
    echo "Killing Microsoft Edge for user: $username"
    pkill -u "$username" -f microsoft-edge 2>/dev/null || true
    pkill -u "$username" -f msedge 2>/dev/null || true
    sleep 2
    pkill -9 -u "$username" -f microsoft-edge 2>/dev/null || true
    pkill -9 -u "$username" -f msedge 2>/dev/null || true
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

# Get Edge window ID
get_edge_window_id() {
    DISPLAY=:1 wmctrl -l | grep -i "edge\|microsoft" | head -1 | awk '{print $1}'
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

# Get Edge profile path
get_profile_path() {
    local username=${1:-ga}
    echo "/home/$username/.config/microsoft-edge/Default"
}

# Check if Bookmarks file exists
check_bookmarks_file() {
    local username=${1:-ga}
    local bookmarks_file="/home/$username/.config/microsoft-edge/Default/Bookmarks"
    if [ -f "$bookmarks_file" ]; then
        echo "$bookmarks_file"
        return 0
    else
        echo ""
        return 1
    fi
}

# Parse Edge bookmarks JSON file
get_edge_bookmarks() {
    local bookmarks_file=${1:-"/home/ga/.config/microsoft-edge/Default/Bookmarks"}

    if [ ! -f "$bookmarks_file" ]; then
        echo ""
        return 1
    fi

    python3 << PYEOF
import json
import sys

try:
    with open("$bookmarks_file", 'r') as f:
        data = json.load(f)

    def extract_bookmarks(node, path=''):
        results = []
        if node.get('type') == 'url':
            results.append({
                'name': node.get('name', ''),
                'url': node.get('url', ''),
                'folder': path
            })
        elif node.get('type') == 'folder':
            new_path = path + '/' + node.get('name', '') if path else node.get('name', '')
            for child in node.get('children', []):
                results.extend(extract_bookmarks(child, new_path))
        return results

    roots = data.get('roots', {})
    all_bookmarks = []
    for root_name, root_node in roots.items():
        if isinstance(root_node, dict):
            all_bookmarks.extend(extract_bookmarks(root_node, root_name))

    print(json.dumps(all_bookmarks))
except Exception as e:
    print(json.dumps([]))
PYEOF
}
TASKUTILSEOF
chmod +x /workspace/utils/task_utils.sh 2>/dev/null || true

echo "=== Microsoft Edge Environment Setup Complete ==="
echo "Edge profile: /home/ga/.config/microsoft-edge/Default"
echo "Launch script: /home/ga/launch_edge.sh"
echo "Utility: /usr/local/bin/edge-util"
