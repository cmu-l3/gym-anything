#!/system/bin/sh
set -e
echo "=== Setting up configure_speed_warnings task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

PACKAGE="com.sygic.aura"
PREFS_DIR="/data/data/$PACKAGE/shared_prefs"
BASELINE_DIR="/tmp/sygic_prefs_before"

# Capture baseline preferences for diffing later
# This helps us detect if the agent actually changed anything
rm -rf "$BASELINE_DIR"
mkdir -p "$BASELINE_DIR"

if [ -d "$PREFS_DIR" ]; then
    echo "Backing up shared preferences..."
    cp "$PREFS_DIR/"*.xml "$BASELINE_DIR/" 2>/dev/null || true
    # Also grab file listing with timestamps
    ls -l "$PREFS_DIR/" > "$BASELINE_DIR/file_list.txt" 2>/dev/null || true
else
    echo "No existing preferences found (fresh install?)"
fi

# Force stop to ensure clean state
am force-stop $PACKAGE
sleep 2

# Launch Sygic to main map view
echo "Launching Sygic GPS..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# Wait for app to load (simple sleep strategy for Android)
sleep 10

# Take initial screenshot
screencap -p /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="