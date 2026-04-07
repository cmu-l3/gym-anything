#!/system/bin/sh
echo "=== Exporting allow_cellular_downloads result ==="

# 1. Define paths
TASK_DIR="/sdcard/tasks/allow_cellular_downloads"
PREFS_DIR="/data/data/com.sygic.aura/shared_prefs"
FINAL_STATE_FILE="/sdcard/final_state.txt"
RESULT_JSON="/sdcard/task_result.json"

# 2. Force stop app to flush preferences to disk
# (Android often keeps prefs in memory until pause/stop)
am force-stop com.sygic.aura
sleep 2

# 3. Capture final preferences state
echo "--- Final Prefs State ---" > "$FINAL_STATE_FILE"
if [ -d "$PREFS_DIR" ]; then
    grep -iE "wifi|connection|download|cellular" "$PREFS_DIR"/*.xml >> "$FINAL_STATE_FILE" 2>/dev/null
fi

# 4. Take final screenshot for verification
screencap -p /sdcard/task_final.png

# 5. Generate Result JSON
# We compare line counts or raw content in the verifier, but here we just export the raw data.
# We'll use python in the verifier to parse the text files.

# Create a JSON wrapper
echo "{" > "$RESULT_JSON"
echo "  \"timestamp\": $(date +%s)," >> "$RESULT_JSON"
echo "  \"initial_state_path\": \"$TASK_DIR/initial_state.txt\"," >> "$RESULT_JSON"
echo "  \"final_state_path\": \"$TASK_DIR/final_state.txt\"," >> "$RESULT_JSON"
echo "  \"screenshot_path\": \"/sdcard/task_final.png\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

# 6. Move files to a location accessible by copy_from_env if needed, 
# but the task structure usually maps /sdcard/tasks/.. so we leave them there 
# or copy to /sdcard/ for easier access if the mapping is strict.
cp "$INITIAL_STATE_FILE" /sdcard/initial_prefs_dump.txt
cp "$FINAL_STATE_FILE" /sdcard/final_prefs_dump.txt

echo "=== Export complete ==="