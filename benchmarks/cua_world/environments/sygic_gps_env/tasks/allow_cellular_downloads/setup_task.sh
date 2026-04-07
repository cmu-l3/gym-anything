#!/system/bin/sh
echo "=== Setting up allow_cellular_downloads task ==="

# 1. Define paths
TASK_DIR="/sdcard/tasks/allow_cellular_downloads"
PREFS_DIR="/data/data/com.sygic.aura/shared_prefs"
INITIAL_STATE_FILE="/sdcard/initial_state.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"

# 2. Record start time for anti-gaming
date +%s > "$START_TIME_FILE"

# 3. Ensure Sygic is installed
if ! pm list packages | grep -q "com.sygic.aura"; then
    echo "ERROR: Sygic not installed"
    exit 1
fi

# 4. Force stop to ensure clean state and readable prefs
am force-stop com.sygic.aura
sleep 1

# 5. Record initial preferences state (filtering for relevant keys)
# We look for keys related to wifi/download restrictions
echo "--- Initial Prefs State ---" > "$INITIAL_STATE_FILE"
if [ -d "$PREFS_DIR" ]; then
    grep -iE "wifi|connection|download|cellular" "$PREFS_DIR"/*.xml >> "$INITIAL_STATE_FILE" 2>/dev/null
else
    echo "Prefs dir not found (first run?)" >> "$INITIAL_STATE_FILE"
fi

# 6. Launch Application
echo "Launching Sygic GPS..."
monkey -p com.sygic.aura -c android.intent.category.LAUNCHER 1
sleep 10

# 7. Ensure we are at the map screen (simple heuristic: press back once in case of overlay)
input keyevent KEYCODE_BACK
sleep 1

echo "=== Setup complete ==="