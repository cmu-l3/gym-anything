#!/bin/bash
echo "=== Setting up migrate_asynctask_to_coroutines task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/task_result.json /tmp/task_start.png /tmp/task_end.png 2>/dev/null || true
rm -f /tmp/gradle_output.log /tmp/original_hashes.txt 2>/dev/null || true

PROJECT_DIR="/home/ga/AndroidStudioProjects/FeedReaderApp"
DATA_SOURCE="/workspace/data/FeedReaderApp"
CALC_SOURCE="/workspace/data/CalculatorApp"

# Fresh copy of data project
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p /home/ga/AndroidStudioProjects
cp -r "$DATA_SOURCE" "$PROJECT_DIR"

# Copy Gradle wrapper binaries from CalculatorApp (binary files not in source)
cp "$CALC_SOURCE/gradlew" "$PROJECT_DIR/gradlew" 2>/dev/null || true
cp "$CALC_SOURCE/gradlew.bat" "$PROJECT_DIR/gradlew.bat" 2>/dev/null || true
mkdir -p "$PROJECT_DIR/gradle/wrapper"
cp "$CALC_SOURCE/gradle/wrapper/gradle-wrapper.jar" "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.jar" 2>/dev/null || true

chown -R ga:ga "$PROJECT_DIR"
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;
chmod +x "$PROJECT_DIR/gradlew"

PKG_DIR="$PROJECT_DIR/app/src/main/java/com/example/feedreader"

# Record original file hashes for change detection
{
    echo "ORIG_BUILD_HASH=$(md5sum "$PROJECT_DIR/app/build.gradle.kts" 2>/dev/null | awk '{print $1}')"
    echo "ORIG_FETCH_HASH=$(md5sum "$PKG_DIR/task/FetchArticlesTask.kt" 2>/dev/null | awk '{print $1}')"
    echo "ORIG_SAVE_HASH=$(md5sum "$PKG_DIR/task/SaveArticleTask.kt" 2>/dev/null | awk '{print $1}')"
    echo "ORIG_SEARCH_HASH=$(md5sum "$PKG_DIR/task/SearchArticlesTask.kt" 2>/dev/null | awk '{print $1}')"
    echo "ORIG_LOAD_HASH=$(md5sum "$PKG_DIR/task/LoadSavedTask.kt" 2>/dev/null | awk '{print $1}')"
    echo "ORIG_FEED_HASH=$(md5sum "$PKG_DIR/ui/FeedActivity.kt" 2>/dev/null | awk '{print $1}')"
    echo "ORIG_SEARCH_ACT_HASH=$(md5sum "$PKG_DIR/ui/SearchActivity.kt" 2>/dev/null | awk '{print $1}')"
    echo "ORIG_REPO_HASH=$(md5sum "$PKG_DIR/repository/ArticleRepository.kt" 2>/dev/null | awk '{print $1}')"
} > /tmp/original_hashes.txt

date +%s > /tmp/task_start_timestamp

setup_android_studio_project "$PROJECT_DIR" "FeedReaderApp" 150
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
