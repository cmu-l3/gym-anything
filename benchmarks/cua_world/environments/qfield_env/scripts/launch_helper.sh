#!/system/bin/sh
# Robust app launch helper with retry logic for QField environment.
# Source this from task setup scripts: . /sdcard/scripts/launch_helper.sh

launch_qfield_project() {
    _LA_PKG="ch.opengis.qfield"
    _LA_GPKG="${1:-/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg}"
    _LA_MAX=5
    _LA_I=1
    while [ "$_LA_I" -le "$_LA_MAX" ]; do
        # Try VIEW intent first (opens specific GeoPackage project)
        am start -a android.intent.action.VIEW \
            -d "file://$_LA_GPKG" \
            -t "application/geopackage+sqlite3" \
            -n "$_LA_PKG/.QFieldActivity" 2>/dev/null
        sleep 10
        # Check if app is in foreground
        if dumpsys window windows 2>/dev/null | grep -q "$_LA_PKG"; then
            echo "QField launched successfully on attempt $_LA_I"
            sleep 5
            return 0
        fi
        # Fallback: try monkey launch
        monkey -p "$_LA_PKG" -c android.intent.category.LAUNCHER 1 2>/dev/null
        sleep 8
        if dumpsys window windows 2>/dev/null | grep -q "$_LA_PKG"; then
            echo "QField launched via monkey on attempt $_LA_I"
            sleep 5
            return 0
        fi
        echo "QField not in foreground, retrying ($_LA_I/$_LA_MAX)..."
        sleep 3
        _LA_I=$((_LA_I + 1))
    done
    echo "WARNING: QField may not have launched after $_LA_MAX attempts"
    return 1
}
