#!/system/bin/sh
# Export script for customize_notification_sound task

echo "=== Exporting results ==="

# 1. Capture final notification state from system
echo "Dumping final notification state..."
dumpsys notification | grep -A 50 "pkg=com.robert.fcView" > /sdcard/final_notification_state.txt

# 2. Record task end time
date +%s > /sdcard/task_end_time.txt

# 3. Capture final screenshot
screencap -p /sdcard/task_final.png

# 4. Check if we are currently in Settings (Context verification)
CURRENT_ACTIVITY=$(dumpsys window windows | grep -E 'mCurrentFocus|mFocusedApp' | grep "com.android.settings")
if [ -n "$CURRENT_ACTIVITY" ]; then
    IN_SETTINGS="true"
else
    IN_SETTINGS="false"
fi

# 5. Create JSON result
# We construct this manually in shell for simplicity/robustness in Android env
cat > /sdcard/task_result.json <<EOF
{
    "timestamp": "$(date +%s)",
    "in_settings_app": $IN_SETTINGS,
    "initial_state_path": "/sdcard/initial_notification_state.txt",
    "final_state_path": "/sdcard/final_notification_state.txt",
    "screenshot_path": "/sdcard/task_final.png"
}
EOF

echo "Result saved to /sdcard/task_result.json"
echo "=== Export complete ==="