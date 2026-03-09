#!/bin/bash
echo "=== Exporting migrate_asynctask_to_coroutines result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/FeedReaderApp"
PKG_DIR="$PROJECT_DIR/app/src/main/java/com/example/feedreader"

take_screenshot /tmp/task_end.png

# Read key source files
BUILD_GRADLE=$(cat "$PROJECT_DIR/app/build.gradle.kts" 2>/dev/null)
FETCH_TASK=$(cat "$PKG_DIR/task/FetchArticlesTask.kt" 2>/dev/null)
SAVE_TASK=$(cat "$PKG_DIR/task/SaveArticleTask.kt" 2>/dev/null)
SEARCH_TASK=$(cat "$PKG_DIR/task/SearchArticlesTask.kt" 2>/dev/null)
LOAD_TASK=$(cat "$PKG_DIR/task/LoadSavedTask.kt" 2>/dev/null)
FEED_ACT=$(cat "$PKG_DIR/ui/FeedActivity.kt" 2>/dev/null)
SEARCH_ACT=$(cat "$PKG_DIR/ui/SearchActivity.kt" 2>/dev/null)
REPO=$(cat "$PKG_DIR/repository/ArticleRepository.kt" 2>/dev/null)

# Change detection
BUILD_CHANGED="false"
FETCH_CHANGED="false"
SAVE_CHANGED="false"
SEARCH_TASK_CHANGED="false"
LOAD_CHANGED="false"
FEED_CHANGED="false"
SEARCH_ACT_CHANGED="false"
REPO_CHANGED="false"

if [ -f /tmp/original_hashes.txt ]; then
    source /tmp/original_hashes.txt
    CURR=$(md5sum "$PROJECT_DIR/app/build.gradle.kts" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_BUILD_HASH" ] && [ -n "$CURR" ] && BUILD_CHANGED="true"
    CURR=$(md5sum "$PKG_DIR/task/FetchArticlesTask.kt" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_FETCH_HASH" ] && [ -n "$CURR" ] && FETCH_CHANGED="true"
    # If FetchArticlesTask.kt is deleted, it counts as changed
    [ ! -f "$PKG_DIR/task/FetchArticlesTask.kt" ] && FETCH_CHANGED="true"
    CURR=$(md5sum "$PKG_DIR/task/SaveArticleTask.kt" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_SAVE_HASH" ] && [ -n "$CURR" ] && SAVE_CHANGED="true"
    [ ! -f "$PKG_DIR/task/SaveArticleTask.kt" ] && SAVE_CHANGED="true"
    CURR=$(md5sum "$PKG_DIR/task/SearchArticlesTask.kt" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_SEARCH_HASH" ] && [ -n "$CURR" ] && SEARCH_TASK_CHANGED="true"
    [ ! -f "$PKG_DIR/task/SearchArticlesTask.kt" ] && SEARCH_TASK_CHANGED="true"
    CURR=$(md5sum "$PKG_DIR/task/LoadSavedTask.kt" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_LOAD_HASH" ] && [ -n "$CURR" ] && LOAD_CHANGED="true"
    [ ! -f "$PKG_DIR/task/LoadSavedTask.kt" ] && LOAD_CHANGED="true"
    CURR=$(md5sum "$PKG_DIR/ui/FeedActivity.kt" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_FEED_HASH" ] && [ -n "$CURR" ] && FEED_CHANGED="true"
    CURR=$(md5sum "$PKG_DIR/ui/SearchActivity.kt" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_SEARCH_ACT_HASH" ] && [ -n "$CURR" ] && SEARCH_ACT_CHANGED="true"
    CURR=$(md5sum "$PKG_DIR/repository/ArticleRepository.kt" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_REPO_HASH" ] && [ -n "$CURR" ] && REPO_CHANGED="true"
fi

# Build
BUILD_SUCCESS="false"
if [ -f "$PROJECT_DIR/gradlew" ]; then
    cd "$PROJECT_DIR"
    chmod +x gradlew 2>/dev/null || true
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_HOME=/opt/android-sdk \
    ./gradlew assembleDebug --no-daemon > /tmp/gradle_output.log 2>&1
    [ $? -eq 0 ] && BUILD_SUCCESS="true"
    if [ "$BUILD_SUCCESS" = "false" ]; then
        JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
        ANDROID_SDK_ROOT=/opt/android-sdk \
        ANDROID_HOME=/opt/android-sdk \
        ./gradlew compileDebugKotlin --no-daemon >> /tmp/gradle_output.log 2>&1
        [ $? -eq 0 ] && BUILD_SUCCESS="true"
    fi
fi
BUILD_OUTPUT=$(tail -40 /tmp/gradle_output.log 2>/dev/null)

# Escape for JSON
BUILD_ESC=$(printf '%s' "$BUILD_GRADLE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
FETCH_ESC=$(printf '%s' "$FETCH_TASK" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
SAVE_ESC=$(printf '%s' "$SAVE_TASK" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
SEARCHK_ESC=$(printf '%s' "$SEARCH_TASK" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
LOAD_ESC=$(printf '%s' "$LOAD_TASK" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
FEED_ESC=$(printf '%s' "$FEED_ACT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
SEARCH_ACT_ESC=$(printf '%s' "$SEARCH_ACT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
REPO_ESC=$(printf '%s' "$REPO" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
BUILD_OUT_ESC=$(printf '%s' "$BUILD_OUTPUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

RESULT_JSON=$(cat << EOF
{
    "build_gradle_content": $BUILD_ESC,
    "build_gradle_changed": $BUILD_CHANGED,
    "fetch_task_content": $FETCH_ESC,
    "fetch_task_changed": $FETCH_CHANGED,
    "save_task_content": $SAVE_ESC,
    "save_task_changed": $SAVE_CHANGED,
    "search_task_content": $SEARCHK_ESC,
    "search_task_changed": $SEARCH_TASK_CHANGED,
    "load_task_content": $LOAD_ESC,
    "load_task_changed": $LOAD_CHANGED,
    "feed_activity_content": $FEED_ESC,
    "feed_activity_changed": $FEED_CHANGED,
    "search_activity_content": $SEARCH_ACT_ESC,
    "search_activity_changed": $SEARCH_ACT_CHANGED,
    "repository_content": $REPO_ESC,
    "repository_changed": $REPO_CHANGED,
    "build_success": $BUILD_SUCCESS,
    "build_output": $BUILD_OUT_ESC,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json
echo "=== Export Complete ==="
