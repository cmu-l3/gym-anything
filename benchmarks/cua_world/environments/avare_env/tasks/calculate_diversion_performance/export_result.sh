#!/system/bin/sh
echo "=== Exporting calculate_diversion_performance results ==="

PACKAGE="com.ds.avare"

# 1. Capture Final Screenshot
screencap -p /sdcard/task_final.png

# 2. Extract Preferences File (Requires root/su to read /data/data)
# We copy it to /sdcard so the verifier can pull it easily
echo "Extracting preferences..."
su 0 cp /data/data/com.ds.avare/shared_prefs/com.ds.avare_preferences.xml /sdcard/task_prefs.xml
chmod 666 /sdcard/task_prefs.xml

# 3. Check for existence of output file
OUTPUT_EXISTS="false"
if [ -f "/sdcard/diversion_calc.txt" ]; then
    OUTPUT_EXISTS="true"
fi

# 4. Check for existence of the saved plan (DivertKFAT)
# Avare usually stores plans in internal files or DB. We'll check the common file location.
# If not found, we rely on the screenshot and calc accuracy.
PLAN_EXISTS="false"
# Try listing files in internal storage
su 0 ls /data/data/com.ds.avare/files/ | grep -q "DivertKFAT" && PLAN_EXISTS="true"

# 5. Create JSON result
# Note: We construct JSON manually in shell
echo "{" > /sdcard/task_result.json
echo "  \"output_exists\": $OUTPUT_EXISTS," >> /sdcard/task_result.json
echo "  \"plan_file_found\": $PLAN_EXISTS," >> /sdcard/task_result.json
echo "  \"timestamp\": \"$(date)\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "Export complete. Files ready in /sdcard/"