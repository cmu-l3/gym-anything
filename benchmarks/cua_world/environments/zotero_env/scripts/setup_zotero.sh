#!/bin/bash
# Note: Do NOT use 'set -e' because Zotero may exit after profile creation

echo "=== Setting up Zotero ==="

# Wait for desktop to be ready
sleep 5

# Create Zotero data directory
mkdir -p /home/ga/Zotero
chown -R ga:ga /home/ga/Zotero

# Create Zotero profile directory
mkdir -p /home/ga/.zotero/zotero
chown -R ga:ga /home/ga/.zotero

# Create prefs.js BEFORE starting Zotero for the first time
echo "Pre-creating profile directory..."
mkdir -p /home/ga/.zotero/zotero
chown -R ga:ga /home/ga/.zotero

# We'll let Zotero create the profile, but configure it with env vars instead
echo "Starting Zotero with configuration..."
# Use environment variables to configure Zotero data directory
sudo -u ga bash -c 'DISPLAY=:1 /opt/zotero/zotero --no-remote > /home/ga/zotero.log 2>&1 &'
echo "Zotero launch command executed"
sleep 15

# Find the created profile
PROFILE_DIR=$(find /home/ga/.zotero/zotero -maxdepth 1 -type d -name "*.default" 2>/dev/null | head -1)

if [ -n "$PROFILE_DIR" ]; then
    echo "Zotero profile directory: $PROFILE_DIR"
    # Add prefs to disable dialogs
    cat >> "$PROFILE_DIR/prefs.js" << 'EOF'
user_pref("extensions.zotero.firstRunGuidance", false);
user_pref("extensions.zotero.firstRun.skipFirefoxProfileAccessCheck", true);
user_pref("extensions.zotero.firstRun2", false);
user_pref("extensions.zotero.reportTranslationFailure", false);
user_pref("extensions.zotero.automaticScraperUpdates", false);
user_pref("extensions.zotero.dataDir", "/home/ga/Zotero");
user_pref("extensions.zotero.useDataDir", true);
user_pref("extensions.zotero.baseAttachmentPath", "/home/ga/Zotero/storage");
EOF
    chown ga:ga "$PROFILE_DIR/prefs.js"
    echo "✓ Configured prefs.js"
else
    echo "✗ Warning: Profile directory not found yet"
fi

# Wait for Zotero window to appear
echo "Waiting for Zotero window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -q "Zotero"; then
        echo "✓ Zotero window detected"
        break
    fi
    echo "  Waiting... ($i/30)"
    sleep 1
done

# Maximize and activate Zotero window
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null && echo "✓ Window maximized" || true
sleep 1
# Activate (raise and focus) the window
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null && echo "✓ Window activated" || echo "⚠ Window activation may have failed"
sleep 2

# Close any Firefox popups/windows that may have opened
echo "Closing Firefox popups..."
pkill -f firefox 2>/dev/null || true
DISPLAY=:1 wmctrl -c "Mozilla Firefox" 2>/dev/null || true
sleep 1

# Dismiss welcome screen by adding a sample item to the database
echo "Initializing library (removing welcome screen)..."
ZOTERO_DB="/home/ga/Zotero/zotero.sqlite"
if [ -f "$ZOTERO_DB" ]; then
    # Add a simple book item to dismiss welcome screen
    # This doesn't interfere with tasks since they track delta (items added)
    sqlite3 "$ZOTERO_DB" << 'SQL'
INSERT INTO items (itemTypeID, dateAdded, dateModified, clientDateModified)
VALUES (2, datetime('now'), datetime('now'), datetime('now'));
SQL
    chown ga:ga "$ZOTERO_DB"
    echo "✓ Sample item added to dismiss welcome screen"
else
    echo "⚠ Database not found, welcome screen may still appear"
fi

# Verify Zotero is running
if ps aux | grep -v grep | grep -q "[z]otero"; then
    echo "✓ Zotero is running"
else
    echo "✗ Warning: Zotero process not found in ps"
    echo "Checking zotero.log for errors..."
    tail -20 /home/ga/zotero.log 2>/dev/null || echo "Log not found"
fi

# Take verification screenshot to confirm Zotero is visible
echo "Taking setup verification screenshot..."
DISPLAY=:1 import -window root /tmp/zotero_setup_verification.png 2>/dev/null && echo "✓ Screenshot saved" || echo "⚠ Screenshot failed"

# Final window list for debugging
echo "Final window list:"
DISPLAY=:1 wmctrl -l

echo "=== Zotero setup complete ==="
