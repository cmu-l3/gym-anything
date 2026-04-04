#!/bin/bash
# post_start hook — configure Floreant POS, run warm-up launch to initialize DB and dismiss dialogs
# Runs as root after the desktop starts

echo "=== Setting up Floreant POS ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Wait for desktop to be fully ready
sleep 8

# Ensure permissions are correct (ga user needs write access for Derby DB)
chown -R ga:ga /opt/floreantpos/
chmod -R 755 /opt/floreantpos/

# Mark the launcher as trusted for the ga user
chmod +x /usr/local/bin/floreant-pos

# -----------------------------------------------------------------------
# Create desktop shortcut (mark as trusted so GNOME opens it)
# -----------------------------------------------------------------------
mkdir -p /home/ga/Desktop

cat > /home/ga/Desktop/FloreantPOS.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=Floreant POS
Comment=Restaurant Point of Sale System
Exec=/usr/local/bin/floreant-pos
Icon=applications-other
StartupNotify=true
Terminal=false
Categories=Office;
Type=Application
DESKTOPEOF
chown ga:ga /home/ga/Desktop/FloreantPOS.desktop
chmod +x /home/ga/Desktop/FloreantPOS.desktop
# Mark as trusted in GNOME (removes the X icon)
su - ga -c "gio set /home/ga/Desktop/FloreantPOS.desktop metadata::trusted true 2>/dev/null" || true

# -----------------------------------------------------------------------
# Warm-up launch: Initialize Derby database and dismiss first-run dialogs
# Note: The Derby database ships pre-populated with the ZIP, but we still
# need a warm-up launch to handle any first-run UI dialogs.
# -----------------------------------------------------------------------
echo "Starting Floreant POS warm-up launch..."

# Kill any stale processes
pkill -f "floreantpos.jar" 2>/dev/null || true
sleep 2

# Launch Floreant POS as user ga using the launcher script (which sets DISPLAY internally)
# CRITICAL: use `setsid /usr/local/bin/floreant-pos` NOT `setsid DISPLAY=:1 java ...`
# setsid requires a real binary as its first argument, not an env var assignment
su - ga -c "setsid /usr/local/bin/floreant-pos > /tmp/floreant_warmup.log 2>&1 &"
echo "Floreant POS launched, waiting for window..."

# Wait for the application window to appear (up to 90 seconds)
TIMEOUT=90
ELAPSED=0
WINDOW_FOUND=false
while [ $ELAPSED -lt $TIMEOUT ]; do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Floreant" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        echo "Floreant POS window found (WID: $WID)"
        WINDOW_FOUND=true
        break
    fi
    # Also check if Java process is running (if it died, log and break)
    if ! pgrep -f "floreantpos.jar" > /dev/null 2>&1; then
        echo "Java process not running, checking log..."
        cat /tmp/floreant_warmup.log 2>/dev/null | tail -20
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

if [ "$WINDOW_FOUND" = "false" ]; then
    echo "WARNING: Floreant window not found after ${ELAPSED}s"
    echo "--- Warmup log ---"
    cat /tmp/floreant_warmup.log 2>/dev/null | tail -30
fi

# Give the app more time to fully render
sleep 5

echo "Waiting for Floreant POS to fully initialize..."
# NOTE: Floreant POS with pre-populated Derby DB starts directly to the main terminal screen.
# No DB connection dialog and no PIN login required at startup.
# The main screen shows: DINE IN, TAKE OUT, RETAIL, HOME DELIVERY, ORDERS, BACK OFFICE, etc.
sleep 10

# Check if still running
if pgrep -f "floreantpos.jar" > /dev/null 2>&1; then
    echo "Java process running — main terminal screen should be visible"

    # Take screenshot to confirm state
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/floreant_warmup_screen.png 2>/dev/null || true
    echo "Warmup screenshot saved to /tmp/floreant_warmup_screen.png"
else
    echo "Java process died during initialization — see log below"
    cat /tmp/floreant_warmup.log 2>/dev/null | tail -30
fi

# Give the application a bit more time
sleep 3

# Kill the warm-up instance
echo "Killing warm-up Floreant instance..."
pkill -f "floreantpos.jar" 2>/dev/null || true
sleep 3
pkill -9 -f "floreantpos.jar" 2>/dev/null || true
sleep 2

# Save a clean DB backup so per-task setup can restore to a pristine state
echo "Saving clean database backup for task resets..."
DB_POSDB=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
if [ -n "$DB_POSDB" ]; then
    cp -r "$DB_POSDB" /opt/floreantpos/posdb_backup
    chown -R ga:ga /opt/floreantpos/posdb_backup
    echo "Database backup saved to /opt/floreantpos/posdb_backup"
else
    # Fallback: backup the whole derby-server dir
    cp -r /opt/floreantpos/database/derby-server /opt/floreantpos/derby_server_backup
    chown -R ga:ga /opt/floreantpos/derby_server_backup
    echo "Derby server backup saved to /opt/floreantpos/derby_server_backup"
fi

# -----------------------------------------------------------------------
# Verify setup
# -----------------------------------------------------------------------
if [ -f "/opt/floreantpos/floreantpos.jar" ]; then
    echo "OK: /opt/floreantpos/floreantpos.jar exists ($(du -sh /opt/floreantpos/floreantpos.jar | cut -f1))"
else
    echo "WARNING: floreantpos.jar not found"
    ls /opt/floreantpos/
fi

# Check Derby database
DB_DIR=$(find /opt/floreantpos/database -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
if [ -n "$DB_DIR" ]; then
    echo "Derby database at: $DB_DIR"
else
    echo "Derby database directory: $(ls -la /opt/floreantpos/database/ 2>/dev/null || echo 'not found')"
fi

echo "=== Floreant POS setup complete ==="
