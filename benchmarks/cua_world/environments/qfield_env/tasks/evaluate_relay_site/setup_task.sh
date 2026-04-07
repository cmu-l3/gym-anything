#!/system/bin/sh
# Setup script for evaluate_relay_site task on Android

echo "=== Setting up evaluate_relay_site task ==="

PACKAGE="ch.opengis.qfield"
SOURCE_GPKG="/sdcard/QFieldData/world_survey.gpkg"
# Note: "Imported Datasets" path handling
DEST_DIR="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets"
DEST_GPKG="$DEST_DIR/world_survey.gpkg"

# 1. Record Start Time
date +%s > /sdcard/task_start_time.txt

# 2. Force Stop QField to ensure clean state
am force-stop $PACKAGE
sleep 2

# 3. Prepare Data
# Create destination directory if it doesn't exist
if [ ! -d "$DEST_DIR" ]; then
    mkdir -p "$DEST_DIR"
fi

# Reset GeoPackage to original state (remove any previous agent edits)
echo "Resetting GeoPackage..."
cp "$SOURCE_GPKG" "$DEST_GPKG"
# Ensure writable permissions for the app
chmod 666 "$DEST_GPKG"

# 4. Launch QField
# We launch to the home screen so the agent has to navigate "Open Local Project"
echo "Launching QField..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# Wait for app to load
sleep 8

# Ensure we are on the main screen (if previous session restored, might need back)
# But force-stop usually clears activity stack.

echo "=== Task Setup Complete ==="
echo "GeoPackage ready at: $DEST_GPKG"