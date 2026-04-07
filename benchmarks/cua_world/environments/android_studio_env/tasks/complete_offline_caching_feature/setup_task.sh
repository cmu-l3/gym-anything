#!/bin/bash
echo "=== Setting up complete_offline_caching_feature task ==="

source /workspace/scripts/task_utils.sh

# Clean up stale artifacts
rm -f /tmp/task_result.json /tmp/task_start.png /tmp/task_end.png 2>/dev/null || true
rm -f /tmp/gradle_output.log /tmp/original_hashes.txt 2>/dev/null || true

# Project paths
PROJECT_DIR="/home/ga/AndroidStudioProjects/StudyPlannerApp"
DATA_SOURCE="/workspace/data/StudyPlannerApp"

# Remove any previous project
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p /home/ga/AndroidStudioProjects

# Copy project from data source
cp -r "$DATA_SOURCE" "$PROJECT_DIR"
chown -R ga:ga "$PROJECT_DIR"
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;

# Copy gradle wrapper from CalculatorApp (standard pattern)
CALC_SOURCE="/workspace/data/CalculatorApp"
if [ -d "$CALC_SOURCE" ]; then
    cp "$CALC_SOURCE/gradlew" "$PROJECT_DIR/gradlew" 2>/dev/null || true
    cp "$CALC_SOURCE/gradlew.bat" "$PROJECT_DIR/gradlew.bat" 2>/dev/null || true
    mkdir -p "$PROJECT_DIR/gradle/wrapper"
    cp "$CALC_SOURCE/gradle/wrapper/gradle-wrapper.jar" "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.jar" 2>/dev/null || true
fi
chown -R ga:ga "$PROJECT_DIR/gradlew" "$PROJECT_DIR/gradlew.bat" "$PROJECT_DIR/gradle/wrapper/" 2>/dev/null || true
chmod +x "$PROJECT_DIR/gradlew"

# Record start timestamp
date +%s > /tmp/task_start_timestamp

# Record original hashes for change detection
{
    echo "ORIG_APP_BUILD_HASH=$(md5sum "$PROJECT_DIR/app/build.gradle.kts" 2>/dev/null | awk '{print $1}')"
    echo "ORIG_CONVERTERS_HASH=$(md5sum "$PROJECT_DIR/app/src/main/java/com/example/studyplanner/data/local/Converters.kt" 2>/dev/null | awk '{print $1}')"
    echo "ORIG_MIGRATIONS_HASH=$(md5sum "$PROJECT_DIR/app/src/main/java/com/example/studyplanner/data/local/Migrations.kt" 2>/dev/null | awk '{print $1}')"
    echo "ORIG_FLASHCARD_DTO_HASH=$(md5sum "$PROJECT_DIR/app/src/main/java/com/example/studyplanner/data/remote/FlashCardDto.kt" 2>/dev/null | awk '{print $1}')"
    echo "ORIG_OFFLINE_REPO_HASH=$(md5sum "$PROJECT_DIR/app/src/main/java/com/example/studyplanner/data/repository/OfflineCacheRepository.kt" 2>/dev/null | awk '{print $1}')"
    echo "ORIG_SUBJECT_VM_HASH=$(md5sum "$PROJECT_DIR/app/src/main/java/com/example/studyplanner/ui/subjects/SubjectListViewModel.kt" 2>/dev/null | awk '{print $1}')"
    echo "ORIG_SESSION_VM_HASH=$(md5sum "$PROJECT_DIR/app/src/main/java/com/example/studyplanner/ui/sessions/SessionLogViewModel.kt" 2>/dev/null | awk '{print $1}')"
} > /tmp/original_hashes.txt

# Open project in Android Studio
setup_android_studio_project "$PROJECT_DIR" "StudyPlannerApp" 150

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
