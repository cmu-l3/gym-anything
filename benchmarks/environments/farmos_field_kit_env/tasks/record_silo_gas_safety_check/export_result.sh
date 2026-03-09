#!/system/bin/sh
# Export script for record_silo_gas_safety_check
# Runs inside the Android environment

echo "=== Exporting Task Results ==="

# 1. Capture final state evidence
echo "Capturing final screenshot..."
screencap -p /sdcard/task_final.png

echo "Dumping UI hierarchy..."
uiautomator dump /sdcard/ui_dump.xml

# 2. Collect timestamps
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check simple file existence (rudimentary check, real check is in verifier.py)
UI_DUMP_EXISTS="false"
if [ -f /sdcard/ui_dump.xml ]; then
    UI_DUMP_EXISTS="true"
fi

# 4. Create result JSON
# Note: We write to a temporary location then move to ensure atomicity if possible,
# though on Android /sdcard is usually FAT/FUSE, so standard permissions apply.
cat > /sdcard/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "ui_dump_exists": $UI_DUMP_EXISTS,
    "screenshot_path": "/sdcard/task_final.png",
    "ui_dump_path": "/sdcard/ui_dump.xml"
}
EOF

echo "Result exported to /sdcard/task_result.json"