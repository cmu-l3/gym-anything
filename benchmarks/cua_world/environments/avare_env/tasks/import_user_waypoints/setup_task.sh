#!/system/bin/sh
echo "=== Setting up import_user_waypoints task ==="

# Record task start time
date +%s > /sdcard/task_start_time.txt

# Define the GPX file content
GPX_PATH="/sdcard/company_lz.gpx"
cat > "$GPX_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="AvareTaskGen" xmlns="http://www.topografix.com/GPX/1/1">
  <wpt lat="37.6150" lon="-122.3900">
    <name>LZ_ALPHA</name>
    <desc>SFO Coast Guard Station</desc>
    <sym>Heliport</sym>
    <type>User</type>
  </wpt>
  <wpt lat="37.8000" lon="-122.2500">
    <name>LZ_BRAVO</name>
    <desc>Oakland Hills Staging</desc>
    <sym>Waypoint</sym>
    <type>User</type>
  </wpt>
  <wpt lat="37.4000" lon="-122.0500">
    <name>LZ_CHARLIE</name>
    <desc>Moffett Federal Airfield</desc>
    <sym>Waypoint</sym>
    <type>User</type>
  </wpt>
</gpx>
EOF

# Also copy to Download folder as it's a common default for file pickers
mkdir -p /sdcard/Download
cp "$GPX_PATH" /sdcard/Download/company_lz.gpx

# Ensure permissions are correct
chmod 666 "$GPX_PATH"
chmod 666 /sdcard/Download/company_lz.gpx

echo "Created GPX file at $GPX_PATH"

PACKAGE="com.ds.avare"

# Force stop Avare to ensure clean state (though we don't wipe data to keep DBs)
am force-stop $PACKAGE
sleep 2

# Press Home to reset UI
input keyevent KEYCODE_HOME
sleep 1

# Launch Avare
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# Capture initial screenshot for evidence
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="