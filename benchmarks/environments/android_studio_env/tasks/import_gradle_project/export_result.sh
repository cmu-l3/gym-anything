#!/bin/bash
set -e

echo "=== Exporting import_gradle_project results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# ------------------------------------------------------------------
# 1. Take final screenshot
# ------------------------------------------------------------------
echo "Taking final screenshot..."
take_screenshot /tmp/screenshot_final.png

# ------------------------------------------------------------------
# 2. Gather evidence from the project directory
# ------------------------------------------------------------------
PROJECT_DIR="/home/ga/AndroidStudioProjects/SunflowerApp"

# Check if .idea/ directory exists (project was opened in IDE)
idea_exists="false"
if [ -d "$PROJECT_DIR/.idea" ]; then
    idea_exists="true"
    echo "Found .idea/ directory - project was opened in IDE"
fi

# Check if Gradle sync created .gradle/ directory in the project
gradle_cache_exists="false"
if [ -d "$PROJECT_DIR/.gradle" ]; then
    gradle_cache_exists="true"
    echo "Found .gradle/ directory - Gradle sync ran"
fi

# Check for build/ directories (Gradle sync may produce these)
build_dir_exists="false"
if [ -d "$PROJECT_DIR/build" ] || [ -d "$PROJECT_DIR/app/build" ]; then
    build_dir_exists="true"
    echo "Found build/ directory - Gradle sync produced build output"
fi

# Read build.gradle.kts content
build_gradle_content=""
if [ -f "$PROJECT_DIR/build.gradle.kts" ]; then
    build_gradle_content=$(cat "$PROJECT_DIR/build.gradle.kts" 2>/dev/null | head -20 || echo "")
    echo "Found top-level build.gradle.kts"
fi

app_build_gradle_content=""
if [ -f "$PROJECT_DIR/app/build.gradle.kts" ]; then
    app_build_gradle_content=$(cat "$PROJECT_DIR/app/build.gradle.kts" 2>/dev/null | head -20 || echo "")
    echo "Found app/build.gradle.kts"
fi

# Check for Plant.kt
plant_kt_exists="false"
plant_kt_path=""
if [ -f "$PROJECT_DIR/app/src/main/java/com/google/samples/apps/sunflower/data/Plant.kt" ]; then
    plant_kt_exists="true"
    plant_kt_path="app/src/main/java/com/google/samples/apps/sunflower/data/Plant.kt"
    echo "Found Plant.kt"
fi

# Check for PlantRepository.kt
plant_repo_exists="false"
plant_repo_path=""
if [ -f "$PROJECT_DIR/app/src/main/java/com/google/samples/apps/sunflower/data/PlantRepository.kt" ]; then
    plant_repo_exists="true"
    plant_repo_path="app/src/main/java/com/google/samples/apps/sunflower/data/PlantRepository.kt"
    echo "Found PlantRepository.kt"
fi

# Read settings.gradle.kts for project name
settings_content=""
if [ -f "$PROJECT_DIR/settings.gradle.kts" ]; then
    settings_content=$(cat "$PROJECT_DIR/settings.gradle.kts" 2>/dev/null || echo "")
    echo "Found settings.gradle.kts"
fi

# Read gradle-wrapper.properties
gradle_wrapper_content=""
if [ -f "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.properties" ]; then
    gradle_wrapper_content=$(cat "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.properties" 2>/dev/null || echo "")
    echo "Found gradle-wrapper.properties"
fi

# Check if Android Studio is still running
android_studio_running="false"
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "android\|studio"; then
    android_studio_running="true"
    echo "Android Studio is running"
fi

# Check window title for project name
window_title=""
if [ "$android_studio_running" = "true" ]; then
    window_title=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "android\|studio" | head -1 | sed 's/^[^ ]* *[^ ]* *[^ ]* *//' || echo "")
    echo "Window title: $window_title"
fi

# ------------------------------------------------------------------
# 3. Write results JSON
# ------------------------------------------------------------------
echo "Writing task_result.json..."

# Escape special characters in strings for JSON
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$1"
}

build_gradle_escaped=$(escape_json "$build_gradle_content")
app_build_gradle_escaped=$(escape_json "$app_build_gradle_content")
settings_escaped=$(escape_json "$settings_content")
gradle_wrapper_escaped=$(escape_json "$gradle_wrapper_content")
window_title_escaped=$(escape_json "$window_title")

JSON_CONTENT=$(cat <<ENDJSON
{
  "idea_dir_exists": $idea_exists,
  "gradle_cache_exists": $gradle_cache_exists,
  "build_dir_exists": $build_dir_exists,
  "build_gradle_content": $build_gradle_escaped,
  "app_build_gradle_content": $app_build_gradle_escaped,
  "plant_kt_exists": $plant_kt_exists,
  "plant_kt_path": "$plant_kt_path",
  "plant_repo_exists": $plant_repo_exists,
  "plant_repo_path": "$plant_repo_path",
  "settings_gradle_content": $settings_escaped,
  "gradle_wrapper_content": $gradle_wrapper_escaped,
  "android_studio_running": $android_studio_running,
  "window_title": $window_title_escaped
}
ENDJSON
)

write_json_result "$JSON_CONTENT" "/tmp/task_result.json"

echo "=== export_result.sh complete ==="
