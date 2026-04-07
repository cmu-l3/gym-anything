#!/system/bin/sh
# Export script for configure_ev_charging task
# Runs inside the Android environment

echo "=== Exporting Results ==="

PACKAGE="com.sygic.aura"
TASK_DIR="/sdcard/tasks/configure_ev_charging"
ARTIFACTS_DIR="$TASK_DIR/artifacts"
PREFS_DIR="/data/data/$PACKAGE/shared_prefs"
RESULT_JSON="$ARTIFACTS_DIR/task_result.json"

# 1. Capture Final Screenshot (Critical for VLM)
screencap -p "$ARTIFACTS_DIR/final_screenshot.png"
echo "Screenshot saved to $ARTIFACTS_DIR/final_screenshot.png"

# 2. Extract Preference Data (File-based verification)
# We look for keywords related to EV mode and connectors in the XML files.
# Sygic prefs are often in com.sygic.aura_preferences.xml or similar.

echo "Extracting preferences..."

# Helper function to grep value from xml files
grep_prefs() {
    keyword=$1
    # Grep in all xmls, return line if found
    grep -i "$keyword" "$PREFS_DIR/"*.xml 2>/dev/null
}

# Check for EV Mode
# Keywords: "ev_mode", "fuel_type", "electric"
EV_MODE_FOUND=$(grep_prefs "electric\|ev_mode\|fuel_type")

# Check for Connectors
# Keywords: "connector", "ccs", "combo", "mennekes", "type2", "chademo"
CONNECTORS_FOUND=$(grep_prefs "connector\|charging\|ccs\|type2\|mennekes\|chademo")

# Save raw grep results to text files for Python verifier to parse
echo "$EV_MODE_FOUND" > "$ARTIFACTS_DIR/ev_prefs_dump.txt"
echo "$CONNECTORS_FOUND" > "$ARTIFACTS_DIR/connector_prefs_dump.txt"

# 3. Create JSON Result
# We construct a simple JSON. Complex parsing happens in Python verifier.
# We just signal if we found ANY relevant keys.

HAS_EV_KEYS="false"
if [ -n "$EV_MODE_FOUND" ]; then HAS_EV_KEYS="true"; fi

HAS_CONNECTOR_KEYS="false"
if [ -n "$CONNECTORS_FOUND" ]; then HAS_CONNECTOR_KEYS="true"; fi

APP_RUNNING="false"
if pidof "$PACKAGE" > /dev/null; then APP_RUNNING="true"; fi

cat > "$RESULT_JSON" <<EOF
{
  "timestamp": $(date +%s),
  "app_running": $APP_RUNNING,
  "has_ev_keys": $HAS_EV_KEYS,
  "has_connector_keys": $HAS_CONNECTOR_KEYS,
  "screenshot_path": "$ARTIFACTS_DIR/final_screenshot.png",
  "prefs_dump_path_ev": "$ARTIFACTS_DIR/ev_prefs_dump.txt",
  "prefs_dump_path_conn": "$ARTIFACTS_DIR/connector_prefs_dump.txt"
}
EOF

echo "Result JSON saved."
cat "$RESULT_JSON"