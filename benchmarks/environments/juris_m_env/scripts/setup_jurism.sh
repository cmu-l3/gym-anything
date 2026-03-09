#!/bin/bash
# Note: Do NOT use 'set -e' because Jurism may exit after profile creation

echo "=== Setting up Juris-M (Jurism) ==="

# Dismiss in-app Jurism alert dialogs by pressing Return on the Jurism window.
# Jurism's "Alert" dialogs (e.g., jurisdiction config notification) are in-app
# XUL dialogs -- they are NOT separate OS windows. xdotool search --name "Alert"
# finds nothing. The fix: target the Jurism window directly.
# Args: $1 = max_seconds to loop (default: 60)
wait_and_dismiss_jurism_alerts() {
    local max_secs="${1:-60}"
    local elapsed=0
    echo "Dismissing Jurism alerts (pressing Return on Jurism window, up to ${max_secs}s)..."
    while [ "$elapsed" -lt "$max_secs" ]; do
        local wid
        wid=$(DISPLAY=:1 xdotool search --name "Jurism" 2>/dev/null | head -1)
        if [ -n "$wid" ]; then
            DISPLAY=:1 xdotool key --window "$wid" Return 2>/dev/null || true
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo "Alert dismissal complete (${elapsed}s elapsed)"
}

# Wait for desktop to be ready
sleep 5

# Create Jurism data directory
mkdir -p /home/ga/Jurism
chown -R ga:ga /home/ga/Jurism

# Create profile directories for both possible locations
mkdir -p /home/ga/.jurism/jurism
mkdir -p /home/ga/.zotero/zotero
chown -R ga:ga /home/ga/.jurism /home/ga/.zotero

# Create Jurism documents directory
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Documents

echo "Starting Jurism for first-run profile creation and jurisdiction configuration..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote > /home/ga/jurism.log 2>&1 &'
echo "Jurism first launch started"

# Wait for Jurism window and dismiss jurisdiction config alert.
# The jurisdiction configuration can take 30-90 seconds, then shows an in-app
# Alert: "Configured 121 jurisdictions. Restart Jurism to install the updated
# configuration." We press Return on the Jurism window to dismiss it.
wait_and_dismiss_jurism_alerts 180

# Close any Firefox popups/windows that may have opened
echo "Closing Firefox popups..."
pkill -f firefox 2>/dev/null || true
DISPLAY=:1 wmctrl -c "Mozilla Firefox" 2>/dev/null || true
sleep 1

# Find the created profile (check both possible locations)
PROFILE_DIR=""
for profile_base in /home/ga/.jurism/jurism /home/ga/.zotero/zotero; do
    found=$(find "$profile_base" -maxdepth 1 -type d -name "*.default" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        PROFILE_DIR="$found"
        echo "Profile found at: $PROFILE_DIR"
        break
    fi
done

if [ -n "$PROFILE_DIR" ]; then
    echo "Jurism profile directory: $PROFILE_DIR"
    # Add prefs to disable dialogs and configure data directory
    cat >> "$PROFILE_DIR/prefs.js" << 'EOF'
user_pref("extensions.zotero.firstRunGuidance", false);
user_pref("extensions.zotero.firstRun.skipFirefoxProfileAccessCheck", true);
user_pref("extensions.zotero.firstRun2", false);
user_pref("extensions.zotero.reportTranslationFailure", false);
user_pref("extensions.zotero.automaticScraperUpdates", false);
user_pref("extensions.zotero.dataDir", "/home/ga/Jurism");
user_pref("extensions.zotero.useDataDir", true);
user_pref("extensions.zotero.baseAttachmentPath", "/home/ga/Jurism/storage");
user_pref("extensions.zotero.sync.autoSync", false);
EOF
    chown ga:ga "$PROFILE_DIR/prefs.js"
    echo "Configured prefs.js"
else
    echo "WARNING: Profile directory not found"
fi

# Find and use the actual Jurism database path
JURISM_DB=""
for db_candidate in /home/ga/Jurism/jurism.sqlite /home/ga/Jurism/zotero.sqlite; do
    if [ -f "$db_candidate" ]; then
        JURISM_DB="$db_candidate"
        echo "Found Jurism database: $JURISM_DB"
        break
    fi
done

if [ -n "$JURISM_DB" ]; then
    # Add a placeholder item to dismiss welcome screen (libraryID=1 and key are required NOT NULL)
    sqlite3 "$JURISM_DB" << 'SQL'
INSERT OR IGNORE INTO items (itemTypeID, dateAdded, dateModified, clientDateModified, libraryID, key)
SELECT 2, datetime('now'), datetime('now'), datetime('now'), 1, 'SETUP001'
WHERE NOT EXISTS (SELECT 1 FROM items WHERE itemTypeID != 14 AND itemTypeID != 1 LIMIT 1);
SQL
    chown ga:ga "$JURISM_DB"
    echo "Jurism database initialized"
fi

# Kill Jurism after profile initialization
echo "Stopping Jurism after initialization..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Relaunch Jurism cleanly (jurisdictions already configured in DB, no config alert)
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote > /home/ga/jurism.log 2>&1 &'
sleep 5

# Wait for second launch to complete and dismiss any residual alerts
wait_and_dismiss_jurism_alerts 60

# Maximize and focus Jurism window
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 2

# Verify Jurism is running
if ps aux | grep -v grep | grep -q "[j]urism"; then
    echo "Jurism is running"
else
    echo "WARNING: Jurism process not found in ps"
    tail -20 /home/ga/jurism.log 2>/dev/null || echo "Log not found"
fi

# Store the database path for tasks to use (specifically jurism.sqlite)
DB_PATH=""
for db_candidate in /home/ga/Jurism/jurism.sqlite /home/ga/Jurism/zotero.sqlite; do
    if [ -f "$db_candidate" ]; then
        DB_PATH="$db_candidate"
        break
    fi
done
if [ -n "$DB_PATH" ]; then
    echo "$DB_PATH" > /tmp/jurism_db_path
    echo "Database path stored: $DB_PATH"
fi

# Take verification screenshot
echo "Taking setup verification screenshot..."
DISPLAY=:1 import -window root /tmp/jurism_setup_verification.png 2>/dev/null && echo "Screenshot saved" || echo "Screenshot failed (trying scrot)"
DISPLAY=:1 scrot /tmp/jurism_setup_verification.png 2>/dev/null || true

# Final window list for debugging
echo "Final window list:"
DISPLAY=:1 wmctrl -l 2>/dev/null || true

echo "=== Jurism setup complete ==="
