#!/bin/bash
set -e
echo "=== Exporting search_functionality result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/EmployeeDirectory"
PACKAGE_PATH="app/src/main/java/com/example/employeedirectory"

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# ------------------------------------------------------------------
# 1. Attempt Compilation (Verify code validity)
# ------------------------------------------------------------------
BUILD_SUCCESS="false"
cd "$PROJECT_DIR"
if [ -f "./gradlew" ]; then
    # We use compileDebugKotlin instead of full assemble to save time, 
    # as we primarily care if the code is valid.
    if su - ga -c "cd $PROJECT_DIR && ./gradlew compileDebugKotlin --no-daemon" > /tmp/build_log.txt 2>&1; then
        BUILD_SUCCESS="true"
    fi
fi

# ------------------------------------------------------------------
# 2. Extract File Contents for Verification
# ------------------------------------------------------------------
MENU_FILE="$PROJECT_DIR/app/src/main/res/menu/main_menu.xml"
ADAPTER_FILE="$PROJECT_DIR/$PACKAGE_PATH/EmployeeAdapter.kt"
ACTIVITY_FILE="$PROJECT_DIR/$PACKAGE_PATH/MainActivity.kt"

MENU_CONTENT=""
if [ -f "$MENU_FILE" ]; then
    MENU_CONTENT=$(cat "$MENU_FILE")
fi

ADAPTER_CONTENT=""
if [ -f "$ADAPTER_FILE" ]; then
    ADAPTER_CONTENT=$(cat "$ADAPTER_FILE")
fi

ACTIVITY_CONTENT=""
if [ -f "$ACTIVITY_FILE" ]; then
    ACTIVITY_CONTENT=$(cat "$ACTIVITY_FILE")
fi

# ------------------------------------------------------------------
# 3. Create JSON Result
# ------------------------------------------------------------------

# Helper to escape JSON string safely in bash
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

MENU_ESCAPED=$(escape_json "$MENU_CONTENT")
ADAPTER_ESCAPED=$(escape_json "$ADAPTER_CONTENT")
ACTIVITY_ESCAPED=$(escape_json "$ACTIVITY_CONTENT")
BUILD_LOG_ESCAPED=$(escape_json "$(head -n 50 /tmp/build_log.txt 2>/dev/null)")

cat > /tmp/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "build_success": $BUILD_SUCCESS,
    "menu_file_exists": $([ -f "$MENU_FILE" ] && echo "true" || echo "false"),
    "menu_content": $MENU_ESCAPED,
    "adapter_content": $ADAPTER_ESCAPED,
    "activity_content": $ACTIVITY_ESCAPED,
    "build_log": $BUILD_LOG_ESCAPED
}
EOF

# ------------------------------------------------------------------
# 4. Optional: Run Unit Test verification (Advanced)
# ------------------------------------------------------------------
# We inject a test file to verify the adapter filter logic actually works.
# This is "Hidden" verification.
TEST_FILE="$PROJECT_DIR/app/src/test/java/com/example/employeedirectory/VerifierAdapterTest.kt"
mkdir -p "$(dirname "$TEST_FILE")"

cat > "$TEST_FILE" <<'EOF'
package com.example.employeedirectory

import org.junit.Test
import org.junit.Assert.*
import android.widget.TextView 
import android.view.View
// Note: Real unit testing of filtering logic inside Adapter often requires robolectric 
// or mocking the ViewHolder/View logic if the filter modifies Views directly.
// However, typically the filter modifies the data list. We will check if the adapter exposes a way to filter.

class VerifierAdapterTest {
    // Since we can't easily mock the RecyclerView dependencies without Robolectric/Mockito in this Env,
    // we will rely on static verification of the source code in verifier.py
    // This file is a placeholder if we wanted to run compiled tests.
}
EOF
# Note: I decided to skip actual execution of injected tests because Adapter logic often depends 
# on Android classes (RecyclerView.Adapter) which require mocking (Mockito) or instrumentation 
# (Robolectric) which might not be set up in the build.gradle by the agent. 
# Static analysis of the source code is more robust here.

echo "Result exported to /tmp/task_result.json"