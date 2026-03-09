#!/bin/bash
echo "=== Setting up add_search_feature task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/task_result.json /tmp/task_start.png /tmp/task_end.png 2>/dev/null || true
rm -f /tmp/gradle_output.log /tmp/original_hashes.txt 2>/dev/null || true

PROJECT_DIR="/home/ga/AndroidStudioProjects/SunflowerApp"
DATA_SOURCE="/workspace/data/SunflowerApp"

rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p /home/ga/AndroidStudioProjects
cp -r "$DATA_SOURCE" "$PROJECT_DIR"
chown -R ga:ga "$PROJECT_DIR"
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;
chmod +x "$PROJECT_DIR/gradlew"

PKG_PATH="com/google/samples/apps/sunflower"

# Record baselines
{
    echo "ORIG_MAIN_HASH=$(md5sum "$PROJECT_DIR/app/src/main/java/$PKG_PATH/MainActivity.kt" 2>/dev/null | awk '{print $1}')"
    echo "ORIG_LAYOUT_HASH=$(md5sum "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" 2>/dev/null | awk '{print $1}')"
    echo "ORIG_STRINGS_HASH=$(md5sum "$PROJECT_DIR/app/src/main/res/values/strings.xml" 2>/dev/null | awk '{print $1}')"
    echo "FILTER_EXISTS=false"
} > /tmp/original_hashes.txt

date +%s > /tmp/task_start_timestamp

setup_android_studio_project "$PROJECT_DIR" "SunflowerApp" 120
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
