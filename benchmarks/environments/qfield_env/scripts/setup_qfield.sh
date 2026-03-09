#!/system/bin/sh
# Post-start setup script for QField GIS environment.
# Runs inside Android emulator via: adb shell sh /sdcard/scripts/setup_qfield.sh
# Installs QField APK and sets up GeoPackage data for field survey tasks.

echo "=== Setting up QField GIS Environment ==="

# Wait for system to be fully ready
sleep 5

# Press Home to ensure we're at home screen
input keyevent KEYCODE_HOME
sleep 2

PACKAGE="ch.opengis.qfield"
APK_PATH="/sdcard/scripts/apks/ch.opengis.qfield.apk"

# Check if QField is already installed
echo "Checking if QField is installed..."
if pm list packages | grep -q "$PACKAGE"; then
    echo "QField: ALREADY INSTALLED"
else
    echo "Installing QField v3.4.6..."

    if [ ! -f "$APK_PATH" ]; then
        echo "ERROR: QField APK not found at $APK_PATH"
        ls -la /sdcard/scripts/apks/ 2>&1
        exit 1
    fi

    # Copy to /data/local/tmp for SELinux compatibility
    cp "$APK_PATH" /data/local/tmp/qfield.apk
    chmod 644 /data/local/tmp/qfield.apk

    # Install APK
    pm install /data/local/tmp/qfield.apk 2>&1
    rm -f /data/local/tmp/qfield.apk

    # Verify installation
    if pm list packages | grep -q "$PACKAGE"; then
        echo "QField installed successfully!"
    else
        echo "ERROR: QField installation failed"
        exit 1
    fi
fi

# Grant required permissions
echo "Granting permissions..."
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null || true
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null || true
pm grant $PACKAGE android.permission.READ_EXTERNAL_STORAGE 2>/dev/null || true
pm grant $PACKAGE android.permission.WRITE_EXTERNAL_STORAGE 2>/dev/null || true
pm grant $PACKAGE android.permission.CAMERA 2>/dev/null || true
pm grant $PACKAGE android.permission.READ_MEDIA_IMAGES 2>/dev/null || true
pm grant $PACKAGE android.permission.READ_MEDIA_VIDEO 2>/dev/null || true

# Set up GeoPackage data in QField's storage directories
# QField's "OPEN LOCAL PROJECT" file browser shows "Imported Datasets" folder by default
QFIELD_DATA="/sdcard/Android/data/ch.opengis.qfield/files"
echo "Setting up GeoPackage data..."
mkdir -p "$QFIELD_DATA"
mkdir -p "$QFIELD_DATA/Imported Datasets"

# Copy to both root and Imported Datasets for maximum compatibility
# The source mount at /sdcard/QFieldData is read-only
cp /sdcard/QFieldData/world_survey.gpkg "$QFIELD_DATA/world_survey.gpkg"
chmod 644 "$QFIELD_DATA/world_survey.gpkg"
cp /sdcard/QFieldData/world_survey.gpkg "$QFIELD_DATA/Imported Datasets/world_survey.gpkg"
chmod 644 "$QFIELD_DATA/Imported Datasets/world_survey.gpkg"

echo "GeoPackage copied to QField storage"
ls -la "$QFIELD_DATA/"

# First-run warmup: launch QField to initialize its state and dismiss tutorial
echo "Launching QField for first-run initialization..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 8

# Dismiss the first-run tutorial popup.
# Tutorial shows "Info Panel" dialog with Next button, then Skip (X) appears.
# Coordinates for 1080x2400 screen:
#   Next step 1: (513, 850) [VG 608,255]
#   Next step 2: (573, 867) [VG 680,260]
#   Skip (X):    (991, 357) [VG 1175,107] - appears after 2+ steps
input tap 513 850  # Next (step 1)
sleep 3
input tap 573 867  # Next (step 2)
sleep 3
input tap 991 357  # Skip (X)
sleep 2
input tap 991 357  # Retry Skip
sleep 3

# Force stop after app tutorial dismissal
am force-stop $PACKAGE
sleep 2

# Second warm-up: open world_survey.gpkg via VIEW intent for the first time.
# QField shows a project-level tutorial on the first GeoPackage open.
# Dismiss it now so all task start states are clean.
echo "Warming up project tutorial (VIEW intent)..."
am start -a android.intent.action.VIEW \
    -d "file:///sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity" 2>/dev/null
sleep 14

# Dismiss project tutorial: same tap sequence as the app tutorial
# Tutorial appears over the map view; Next advances steps, Skip (X) dismisses
input tap 513 850  # Next (step 1)
sleep 2
input tap 573 867  # Next (step 2)
sleep 2
input tap 991 357  # Skip (X)
sleep 2
input tap 991 357  # Retry Skip
sleep 3

# Force stop for final clean state
am force-stop $PACKAGE
sleep 2

echo "=== QField GIS environment setup complete ==="
echo "GeoPackage: /sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg"
echo "Contains: 87 world capitals + 8 field observations"
