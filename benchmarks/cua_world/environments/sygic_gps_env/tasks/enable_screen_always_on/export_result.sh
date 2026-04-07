#!/system/bin/sh
echo "=== Exporting enable_screen_always_on results ==="

PACKAGE="com.sygic.aura"
ARTIFACTS_DIR="/sdcard/task_artifacts"
mkdir -p "$ARTIFACTS_DIR"

# 1. Take final screenshot
screencap -p "$ARTIFACTS_DIR/final_state.png"

# 2. Export SharedPreferences for verification
# We copy them to /sdcard so the host verifier can pull them via copy_from_env
PREFS_DIR="/data/data/$PACKAGE/shared_prefs"
EXPORT_PREFS_DIR="$ARTIFACTS_DIR/final_prefs"
mkdir -p "$EXPORT_PREFS_DIR"

if [ -d "$PREFS_DIR" ]; then
    cp "$PREFS_DIR/"*.xml "$EXPORT_PREFS_DIR/" 2>/dev/null
    chmod 666 "$EXPORT_PREFS_DIR/"*.xml 2>/dev/null
fi

# 3. Export Database (some settings might be here)
DB_DIR="/data/data/$PACKAGE/databases"
EXPORT_DB_DIR="$ARTIFACTS_DIR/final_dbs"
mkdir -p "$EXPORT_DB_DIR"

if [ -d "$DB_DIR" ]; then
    cp "$DB_DIR/"* "$EXPORT_DB_DIR/" 2>/dev/null
    chmod 666 "$EXPORT_DB_DIR/"* 2>/dev/null
fi

# 4. Capture System State (Window Manager & Power Manager)
# This detects if FLAG_KEEP_SCREEN_ON is active
dumpsys window windows | grep -A15 "com.sygic.aura" > "$ARTIFACTS_DIR/dumpsys_window.txt"
dumpsys power > "$ARTIFACTS_DIR/dumpsys_power.txt"

# 5. Create summary JSON
TASK_START=$(cat "$ARTIFACTS_DIR/task_start_time.txt" 2>/dev/null || echo "0")
TASK_END=$(date +%s)

cat > "$ARTIFACTS_DIR/task_result.json" <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "package": "$PACKAGE",
    "artifacts_path": "$ARTIFACTS_DIR"
}
EOF

echo "=== Export complete ==="