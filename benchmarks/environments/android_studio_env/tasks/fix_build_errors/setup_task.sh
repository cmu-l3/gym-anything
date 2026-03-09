#!/bin/bash
echo "=== Setting up fix_build_errors task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Clean up any previous task artifacts
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_start.png /tmp/task_end.png 2>/dev/null || true
rm -f /tmp/gradle_output.log /tmp/gradle_sync_output.log 2>/dev/null || true
rm -f /tmp/original_hashes.txt 2>/dev/null || true

# Project paths
PROJECT_DIR="/home/ga/AndroidStudioProjects/BrokenApp"
DATA_SOURCE="/workspace/data/BrokenApp"

# Remove any existing BrokenApp project so we start fresh
rm -rf "$PROJECT_DIR" 2>/dev/null || true

# Copy BrokenApp from data directory to user's project space
mkdir -p /home/ga/AndroidStudioProjects
cp -r "$DATA_SOURCE" "$PROJECT_DIR"

# Set ownership and permissions
chown -R ga:ga "$PROJECT_DIR"
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;

# Make gradlew executable
chmod +x "$PROJECT_DIR/gradlew"

# Record file hashes of original broken files (for integrity check to confirm changes were made)
MAIN_ACTIVITY="$PROJECT_DIR/app/src/main/java/com/google/samples/apps/sunflower/MainActivity.kt"
PLANT_KT="$PROJECT_DIR/app/src/main/java/com/google/samples/apps/sunflower/data/Plant.kt"
PLANT_REPO="$PROJECT_DIR/app/src/main/java/com/google/samples/apps/sunflower/data/PlantRepository.kt"
BUILD_GRADLE="$PROJECT_DIR/app/build.gradle.kts"

{
    echo "ORIG_MAIN_HASH=$(md5sum "$MAIN_ACTIVITY" 2>/dev/null | awk '{print $1}')"
    echo "ORIG_PLANT_HASH=$(md5sum "$PLANT_KT" 2>/dev/null | awk '{print $1}')"
    echo "ORIG_REPO_HASH=$(md5sum "$PLANT_REPO" 2>/dev/null | awk '{print $1}')"
    echo "ORIG_GRADLE_HASH=$(md5sum "$BUILD_GRADLE" 2>/dev/null | awk '{print $1}')"
} > /tmp/original_hashes.txt

echo "Original file hashes recorded:"
cat /tmp/original_hashes.txt

# Open the project in Android Studio
setup_android_studio_project "$PROJECT_DIR" "BrokenApp" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
