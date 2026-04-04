#!/bin/bash
set -e

echo "=== Exporting add_bottom_navigation result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/NavigationApp"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Collect File Contents
# We read key files to verify their content in Python
# Using python one-liner to escape JSON strings safely

escape_file_content() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        cat "$fpath" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""'
    else
        echo '""'
    fi
}

file_exists_bool() {
    if [ -f "$1" ]; then echo "true"; else echo "false"; fi
}

# Paths
BUILD_GRADLE="$PROJECT_DIR/app/build.gradle.kts"
ACTIVITY_MAIN="$PROJECT_DIR/app/src/main/res/layout/activity_main.xml"
MAIN_ACTIVITY="$PROJECT_DIR/app/src/main/java/com/example/navapp/MainActivity.kt"
NAV_GRAPH="$PROJECT_DIR/app/src/main/res/navigation/nav_graph.xml"
MENU_FILE="$PROJECT_DIR/app/src/main/res/menu/bottom_nav_menu.xml"

# Fragments
FRAG_HOME="$PROJECT_DIR/app/src/main/java/com/example/navapp/HomeFragment.kt"
FRAG_DASH="$PROJECT_DIR/app/src/main/java/com/example/navapp/DashboardFragment.kt"
FRAG_SETT="$PROJECT_DIR/app/src/main/java/com/example/navapp/SettingsFragment.kt"

# Layouts
LAY_HOME="$PROJECT_DIR/app/src/main/res/layout/fragment_home.xml"
LAY_DASH="$PROJECT_DIR/app/src/main/res/layout/fragment_dashboard.xml"
LAY_SETT="$PROJECT_DIR/app/src/main/res/layout/fragment_settings.xml"

# Prepare JSON fields
build_gradle_content=$(escape_file_content "$BUILD_GRADLE")
activity_main_content=$(escape_file_content "$ACTIVITY_MAIN")
main_activity_content=$(escape_file_content "$MAIN_ACTIVITY")
nav_graph_content=$(escape_file_content "$NAV_GRAPH")
menu_content=$(escape_file_content "$MENU_FILE")

frag_home_exists=$(file_exists_bool "$FRAG_HOME")
frag_dash_exists=$(file_exists_bool "$FRAG_DASH")
frag_sett_exists=$(file_exists_bool "$FRAG_SETT")

lay_home_exists=$(file_exists_bool "$LAY_HOME")
lay_dash_exists=$(file_exists_bool "$LAY_DASH")
lay_sett_exists=$(file_exists_bool "$LAY_SETT")

# 3. Attempt Build (if possible)
# Since we created a dummy gradlew that relies on system gradle, check if it works
build_success="false"
build_output=""

if [ -f "$PROJECT_DIR/gradlew" ]; then
    echo "Attempting build..."
    cd "$PROJECT_DIR"
    
    # Try using Android Studio's bundled java
    export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
    export ANDROID_SDK_ROOT=/opt/android-sdk
    
    # If system gradle exists or wrapper exists
    if ./gradlew assembleDebug --no-daemon > /tmp/build_output.log 2>&1; then
        build_success="true"
    else
        # If the dummy gradlew fails (no system gradle), we might try to find gradle in /opt/android-studio
        # But mostly we rely on file content if build fails due to env issues
        echo "Build failed or gradle not found."
    fi
    
    # Capture last 50 lines of output
    if [ -f /tmp/build_output.log ]; then
        build_output=$(tail -n 50 /tmp/build_output.log | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
    else
        build_output='""'
    fi
else
    build_output='""'
fi

# 4. Construct JSON Result
cat > /tmp/task_result.json <<EOF
{
  "task_start_time": $TASK_START,
  "build_gradle_content": $build_gradle_content,
  "activity_main_content": $activity_main_content,
  "main_activity_content": $main_activity_content,
  "nav_graph_content": $nav_graph_content,
  "menu_content": $menu_content,
  "frag_home_exists": $frag_home_exists,
  "frag_dash_exists": $frag_dash_exists,
  "frag_sett_exists": $frag_sett_exists,
  "lay_home_exists": $lay_home_exists,
  "lay_dash_exists": $lay_dash_exists,
  "lay_sett_exists": $lay_sett_exists,
  "build_success": $build_success,
  "build_output": $build_output,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json