#!/bin/bash
# post_start hook: Configure LibreOffice Base and run warm-up to dismiss first-run dialogs.
# Runs after the desktop (GNOME) is available.
set -e

echo "=== Setting up LibreOffice Base ==="

# Wait for desktop to be fully ready
sleep 5

# --- Verify required files exist ---
if [ ! -f /opt/libreoffice_base_samples/chinook.odb ]; then
    echo "ERROR: chinook.odb missing from /opt/libreoffice_base_samples/" >&2
    ls -la /opt/libreoffice_base_samples/ || true
    exit 1
fi

ODB_SIZE=$(stat -c%s /opt/libreoffice_base_samples/chinook.odb)
if [ "$ODB_SIZE" -lt 10000 ]; then
    echo "ERROR: chinook.odb too small (${ODB_SIZE} bytes)" >&2
    exit 1
fi
echo "Verified chinook.odb: ${ODB_SIZE} bytes"

# --- Pre-configure LibreOffice to suppress first-run dialogs ---
LO_CONFIG_DIR="/home/ga/.config/libreoffice/4/user"
mkdir -p "$LO_CONFIG_DIR"

cat > "$LO_CONFIG_DIR/registrymodifications.xcu" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<oor:items xmlns:oor="http://openoffice.org/2001/registry" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
 <!-- Skip first-run wizard -->
 <item oor:path="/org.openoffice.Setup/Office">
  <prop oor:name="FirstRunWizardFinished" oor:op="fuse"><value>true</value></prop>
 </item>
 <item oor:path="/org.openoffice.Setup/Office">
  <prop oor:name="ShowLicenseAcceptance" oor:op="fuse"><value>false</value></prop>
 </item>
 <!-- Disable update check -->
 <item oor:path="/org.openoffice.Office.Common/Update/AutoUpdate">
  <prop oor:name="Enabled" oor:op="fuse"><value>false</value></prop>
 </item>
 <!-- Disable crash reporter -->
 <item oor:path="/org.openoffice.Office.Common/Misc">
  <prop oor:name="CrashReport" oor:op="fuse"><value>false</value></prop>
 </item>
 <!-- Disable telemetry -->
 <item oor:path="/org.openoffice.Office.Common/Misc">
  <prop oor:name="CollectUsageInformation" oor:op="fuse"><value>false</value></prop>
 </item>
 <!-- Enable Java (required for HSQLDB) -->
 <item oor:path="/org.openoffice.Office.Java">
  <prop oor:name="Enable" oor:op="fuse"><value>true</value></prop>
 </item>
 <!-- Disable recent documents list (cleaner start state) -->
 <item oor:path="/org.openoffice.Office.Common/History">
  <prop oor:name="PickListSize" oor:op="fuse"><value>0</value></prop>
 </item>
</oor:items>
EOF

chown -R ga:ga /home/ga/.config/libreoffice

# --- Copy Chinook ODB to user's home ---
cp /opt/libreoffice_base_samples/chinook.odb /home/ga/chinook.odb
chown ga:ga /home/ga/chinook.odb
chmod 644 /home/ga/chinook.odb

echo "Copied chinook.odb to /home/ga/"

# --- Warm-up launch: dismiss first-run dialogs ---
# LibreOffice Base may show: registration dialog, Java config dialog,
# HSQLDB deprecation dialog. Dismiss them all so subsequent launches are clean.

echo "Starting LibreOffice Base warm-up launch..."

su - ga -c "DISPLAY=:1 soffice --nofirststartwizard --norestore /home/ga/chinook.odb &" &
SOFFICE_BG_PID=$!

# Wait for LibreOffice window to appear (up to 40 seconds)
echo "Waiting for LibreOffice Base window..."
WINDOW_FOUND=false
for i in $(seq 1 40); do
    WID=$(DISPLAY=:1 xdotool search --name "chinook" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        echo "LibreOffice Base window appeared after ${i}s (WID: $WID)"
        WINDOW_FOUND=true
        break
    fi
    # Also check for any LibreOffice window (Start Center, etc.)
    WID=$(DISPLAY=:1 xdotool search --class "soffice" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        echo "LibreOffice window appeared after ${i}s (class soffice)"
        WINDOW_FOUND=true
        break
    fi
    sleep 1
done

if [ "$WINDOW_FOUND" = "false" ]; then
    echo "WARNING: LibreOffice window did not appear within 40s, continuing anyway"
fi

# Give dialogs time to appear, then dismiss them
sleep 3

# Dismiss any modal dialogs: press Escape and Enter multiple times
for attempt in 1 2 3 4 5; do
    # Try pressing Escape to dismiss dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    # Also try Enter in case a dialog needs confirmation
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 0.5
done

# Check for HSQLDB migration dialog: "Keep Current Format" is typically the first button
# The dialog title contains "Database" or "Migration"
MIGRATION_WID=$(DISPLAY=:1 xdotool search --name "Migration" 2>/dev/null | head -1)
if [ -n "$MIGRATION_WID" ]; then
    echo "Found HSQLDB migration dialog, pressing Escape to keep current format..."
    DISPLAY=:1 xdotool windowfocus "$MIGRATION_WID" 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
fi

# Wait a bit more for the app to settle
sleep 3

# Kill LibreOffice after warm-up
echo "Killing LibreOffice after warm-up..."
pkill -f "soffice" 2>/dev/null || true
pkill -f "soffice.bin" 2>/dev/null || true
sleep 3

# Final cleanup: ensure no LibreOffice processes remain
pkill -9 -f "soffice" 2>/dev/null || true
sleep 1

echo "Warm-up complete. LibreOffice Base is configured and ready."
echo "=== LibreOffice Base setup complete ==="
