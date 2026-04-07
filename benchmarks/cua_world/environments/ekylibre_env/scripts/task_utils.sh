#!/bin/bash
# Ekylibre task utilities - shared functions for all task setup scripts
# Source this from setup_task.sh files:
#   source /workspace/scripts/task_utils.sh

EKYLIBRE_URL="http://demo.ekylibre.farm:3000"
EKYLIBRE_FALLBACK_URL="http://demo.ekylibre.local:3000"
ADMIN_EMAIL="admin@ekylibre.org"
ADMIN_PASSWORD="12345678"

# Detect the actual working URL
detect_ekylibre_url() {
    for URL in "$EKYLIBRE_URL" "$EKYLIBRE_FALLBACK_URL" "http://demo.ekylibre.lan:3000" "http://default.ekylibre.lan:3000" "http://localhost:3000"; do
        code=$(curl -s -o /dev/null -w "%{http_code}" "$URL" 2>/dev/null || echo "000")
        if [ "$code" = "200" ] || [ "$code" = "302" ] || [ "$code" = "301" ]; then
            echo "$URL"
            return 0
        fi
    done
    # Default to demo URL
    echo "$EKYLIBRE_URL"
}

# Wait for Ekylibre to be accessible
wait_for_ekylibre() {
    local timeout="${1:-120}"
    local elapsed=0
    local url

    url=$(detect_ekylibre_url)

    echo "Waiting for Ekylibre at $url..."
    while [ "$elapsed" -lt "$timeout" ]; do
        code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        if [ "$code" = "200" ] || [ "$code" = "302" ] || [ "$code" = "301" ]; then
            echo "Ekylibre ready (HTTP $code) after ${elapsed}s"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo "WARNING: Ekylibre may not be ready (timeout ${timeout}s)"
    return 1
}

# Ensure Firefox profile exists with comprehensive first-run suppression
ensure_firefox_profile() {
    SNAP_FF_DIR="/home/ga/snap/firefox/common/.mozilla/firefox"
    STD_FF_DIR="/home/ga/.mozilla/firefox"

    if [ -d "/snap/firefox" ] || snap list firefox 2>/dev/null | grep -q firefox; then
        FF_PROFILE_ROOT="$SNAP_FF_DIR"
    else
        FF_PROFILE_ROOT="$STD_FF_DIR"
    fi

    local PROFILE_DIR="$FF_PROFILE_ROOT/ekylibre.profile"
    mkdir -p "$PROFILE_DIR"

    # Write profiles.ini if missing
    if [ ! -f "$FF_PROFILE_ROOT/profiles.ini" ]; then
        cat > "$FF_PROFILE_ROOT/profiles.ini" << 'FFPROFILE'
[Install4F96D1932A9F858E]
Default=ekylibre.profile
Locked=1

[Profile0]
Name=ekylibre
IsRelative=1
Path=ekylibre.profile
Default=1

[General]
StartWithLastProfile=1
Version=2
FFPROFILE
    fi

    # Always refresh user.js with comprehensive first-run suppression
    cat > "$PROFILE_DIR/user.js" << 'USERJS'
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("datareporting.policy.dataSubmissionPolicyAcceptedVersion", 2);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);
user_pref("startup.homepage_welcome_url", "");
user_pref("startup.homepage_welcome_url.additional", "");
user_pref("trailhead.firstrun.didSeeAboutWelcome", true);
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("browser.vpn_promo.enabled", false);
user_pref("browser.uitour.enabled", false);
user_pref("extensions.pocket.enabled", false);
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
user_pref("browser.startup.page", 0);
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.aboutConfig.showWarning", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("browser.places.importBookmarksHTML", false);
user_pref("browser.bookmarks.addedImportButton", true);
user_pref("browser.toolbars.bookmarks.visibility", "never");
USERJS

    # Fix snap Firefox data directory permissions
    if [ "$FF_PROFILE_ROOT" = "$SNAP_FF_DIR" ]; then
        local SNAP_FF_VERSION
        SNAP_FF_VERSION=$(snap list firefox 2>/dev/null | awk '/firefox/{print $3}')
        if [ -n "$SNAP_FF_VERSION" ]; then
            mkdir -p "/home/ga/snap/firefox/$SNAP_FF_VERSION"
        fi
    fi

    chown -R ga:ga "$(dirname "$FF_PROFILE_ROOT")" 2>/dev/null || \
    chown -R ga:ga "$FF_PROFILE_ROOT" 2>/dev/null || true
}

# Navigate Firefox to a URL robustly (focus + address bar + type + enter)
_navigate_firefox_to() {
    local url="$1"
    local WID
    WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
          xdotool search --class Firefox 2>/dev/null | tail -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool windowactivate "$WID" 2>/dev/null || true
        sleep 0.5
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key --window "$WID" ctrl+l 2>/dev/null || true
        sleep 0.3
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool type --clearmodifiers "$url" 2>/dev/null || true
        sleep 0.2
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key --window "$WID" Return 2>/dev/null || true
        return 0
    fi
    return 1
}

# Ensure Firefox is running with Ekylibre
ensure_firefox_with_ekylibre() {
    local url="${1:-}"
    if [ -z "$url" ]; then
        url=$(detect_ekylibre_url)
    fi

    # Ensure profile exists with first-run suppression before any Firefox launch
    ensure_firefox_profile

    SNAP_FF_DIR="/home/ga/snap/firefox/common/.mozilla/firefox"
    STD_FF_DIR="/home/ga/.mozilla/firefox"

    if [ -d "/snap/firefox" ] || snap list firefox 2>/dev/null | grep -q firefox; then
        PROFILE_PATH="$SNAP_FF_DIR/ekylibre.profile"
    else
        PROFILE_PATH="$STD_FF_DIR/ekylibre.profile"
    fi

    # Check if Firefox is running
    if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
        # Firefox is running — navigate to URL
        _navigate_firefox_to "$url"
    else
        # Firefox not running — launch it fresh
        pkill -f firefox 2>/dev/null || true
        sleep 1

        rm -f "$PROFILE_PATH/.parentlock" "$PROFILE_PATH/lock" 2>/dev/null || true

        if [ -d "/snap/firefox" ] || snap list firefox 2>/dev/null | grep -q firefox; then
            su - ga -c "
                rm -f '$PROFILE_PATH/.parentlock' '$PROFILE_PATH/lock' 2>/dev/null || true
                DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
                setsid firefox --new-instance \
                -profile '$PROFILE_PATH' \
                '$url' > /tmp/firefox_task.log 2>&1 &
            "
        else
            su - ga -c "
                DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
                XDG_RUNTIME_DIR=/run/user/1000 \
                DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
                setsid firefox --new-instance \
                -profile '$PROFILE_PATH' \
                '$url' > /tmp/firefox_task.log 2>&1 &
            "
        fi

        # Wait for Firefox window
        for i in $(seq 1 30); do
            if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
                break
            fi
            sleep 1
        done
    fi

    sleep 3

    # Check if Firefox opened to a welcome/privacy page instead of target URL
    # If so, forcibly navigate to the correct URL
    local win_title
    win_title=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 || true)
    if echo "$win_title" | grep -qiE "welcome|privacy|mozilla firefox$|new tab|about:"; then
        echo "Detected Firefox welcome/privacy page, navigating to $url..."
        _navigate_firefox_to "$url"
        sleep 3
    fi
}

# Maximize Firefox window
maximize_firefox() {
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 0.5
}

# Navigate Firefox to a specific URL
navigate_to() {
    local url="$1"
    local WID
    WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
          xdotool search --class Firefox 2>/dev/null | tail -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool windowactivate "$WID" 2>/dev/null || true
        sleep 0.3
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key --window "$WID" ctrl+l 2>/dev/null || true
        sleep 0.3
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool type --clearmodifiers "$url" 2>/dev/null || true
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key --window "$WID" Return 2>/dev/null || true
        sleep 3
    fi
}

# Query Ekylibre database
ekylibre_db_query() {
    local query="$1"
    docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A -c "$query" 2>/dev/null \
        || echo ""
}

# Take a screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot "$path" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root "$path" 2>/dev/null || true
}
