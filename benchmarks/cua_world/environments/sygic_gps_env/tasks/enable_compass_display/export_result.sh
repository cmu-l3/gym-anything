#!/system/bin/sh
echo "=== Exporting enable_compass_display results ==="

# Record end time
date +%s > /sdcard/task_end_time.txt

# Capture final screenshot (CRITICAL for VLM verification)
screencap -p /sdcard/task_final.png

# Dump UI hierarchy (secondary signal)
# This might reveal if the compass view element exists and is visible
uiautomator dump /sdcard/ui_dump.xml 2>/dev/null

# Try to export SharedPreferences for programmatic verification
# We copy to sdcard because direct access to /data/data might be restricted for the agent user
# but the script runs as root/system in this env usually, or we use run-as.
# We'll attempt a copy.
mkdir -p /sdcard/task_evidence
if [ -d "/data/data/com.sygic.aura/shared_prefs" ]; then
    cp -r /data/data/com.sygic.aura/shared_prefs/* /sdcard/task_evidence/ 2>/dev/null
    chmod 666 /sdcard/task_evidence/* 2>/dev/null
fi

# Create a JSON summary
cat > /sdcard/task_result.json <<EOF
{
    "timestamp": "$(date +%s)",
    "final_screenshot": "/sdcard/task_final.png",
    "ui_dump": "/sdcard/ui_dump.xml",
    "prefs_exported": $(ls /sdcard/task_evidence/*.xml >/dev/null 2>&1 && echo "true" || echo "false")
}
EOF

echo "=== Export complete ==="