#!/bin/bash
echo "=== Setting up implement_room_database task ==="

source /workspace/scripts/task_utils.sh

# Clean up previous artifacts
rm -f /tmp/task_result.json /tmp/task_start.png /tmp/task_end.png 2>/dev/null || true
rm -f /tmp/gradle_output.log /tmp/original_hashes.txt 2>/dev/null || true

PROJECT_DIR="/home/ga/AndroidStudioProjects/SunflowerApp"
DATA_SOURCE="/workspace/data/SunflowerApp"

# Fresh copy of SunflowerApp
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p /home/ga/AndroidStudioProjects
cp -r "$DATA_SOURCE" "$PROJECT_DIR"
chown -R ga:ga "$PROJECT_DIR"
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;
chmod +x "$PROJECT_DIR/gradlew"

# Record baseline hashes of files that should be modified
PKG_PATH="com/google/samples/apps/sunflower"
{
    echo "ORIG_PLANT_HASH=$(md5sum "$PROJECT_DIR/app/src/main/java/$PKG_PATH/data/Plant.kt" 2>/dev/null | awk '{print $1}')"
    echo "ORIG_REPO_HASH=$(md5sum "$PROJECT_DIR/app/src/main/java/$PKG_PATH/data/PlantRepository.kt" 2>/dev/null | awk '{print $1}')"
    echo "ORIG_BUILD_HASH=$(md5sum "$PROJECT_DIR/app/build.gradle.kts" 2>/dev/null | awk '{print $1}')"
} > /tmp/original_hashes.txt

# Record that PlantDao.kt and PlantDatabase.kt do NOT exist yet
echo "DAO_EXISTS=false" >> /tmp/original_hashes.txt
echo "DB_EXISTS=false" >> /tmp/original_hashes.txt

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Open the project in Android Studio
setup_android_studio_project "$PROJECT_DIR" "SunflowerApp" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
