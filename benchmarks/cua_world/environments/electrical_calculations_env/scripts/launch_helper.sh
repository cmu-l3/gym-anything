#!/system/bin/sh
# Robust app launch helper for Electrical Calculations environment.
# Source this from task setup scripts: . /sdcard/scripts/launch_helper.sh
# IMPORTANT: This file is for electrical_calculations_env ONLY.
# Do NOT replace the function name or package - they must match this env.

launch_electrical_calc() {
    _LA_PKG="com.hsn.electricalcalculations"
    _LA_MAX=5
    _LA_I=1
    while [ "$_LA_I" -le "$_LA_MAX" ]; do
        input keyevent KEYCODE_WAKEUP 2>/dev/null || true
        monkey -p "$_LA_PKG" -c android.intent.category.LAUNCHER 1 2>/dev/null || true
        sleep 8
        if dumpsys window windows 2>/dev/null | grep -q "$_LA_PKG"; then
            echo "App launched successfully on attempt $_LA_I"
            return 0
        fi
        echo "App not in foreground, retrying ($_LA_I/$_LA_MAX)..."
        sleep 3
        _LA_I=$((_LA_I + 1))
    done
    echo "WARNING: App may not have launched after $_LA_MAX attempts"
    return 0
}
