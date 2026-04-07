#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting React Webpack Optimization Result ==="

WORKSPACE_DIR="/home/ga/workspace/news_portal"
RESULT_FILE="/tmp/webpack_result.json"

# Best-effort: focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Take final screenshot
take_screenshot /tmp/task_final.png

cd "$WORKSPACE_DIR"

# Test 1: Run Jest
echo "Running tests..."
TEST_PASSED=false
if sudo -u ga npm test > /tmp/test_output.log 2>&1; then
    TEST_PASSED=true
fi

# Test 2: Run Webpack Build
echo "Running build..."
BUILD_PASSED=false
if sudo -u ga npm run build > /tmp/build_output.log 2>&1; then
    BUILD_PASSED=true
fi

# Collect outputs
JS_FILES_COUNT=$(find dist -name "*.js" 2>/dev/null | wc -l || echo "0")
CSS_FILES_COUNT=$(find dist -name "*.css" 2>/dev/null | wc -l || echo "0")
JS_FILES=$(find dist -name "*.js" -exec basename {} \; 2>/dev/null | paste -sd "," - || echo "")
CSS_FILES=$(find dist -name "*.css" -exec basename {} \; 2>/dev/null | paste -sd "," - || echo "")

# Read source files for regex analysis
WEBPACK_CONFIG=$(cat webpack.config.js 2>/dev/null || echo "")
APP_JS=$(cat src/App.js 2>/dev/null || echo "")
FORMATTERS_JS=$(cat src/utils/formatters.js 2>/dev/null || echo "")

# Write everything to JSON
python3 << PYEXPORT
import json
import os

result = {
    "test_passed": ${TEST_PASSED},
    "build_passed": ${BUILD_PASSED},
    "dist_js_count": int("${JS_FILES_COUNT}"),
    "dist_css_count": int("${CSS_FILES_COUNT}"),
    "js_files": "${JS_FILES}".split(",") if "${JS_FILES}" else [],
    "css_files": "${CSS_FILES}".split(",") if "${CSS_FILES}" else [],
    "sources": {
        "webpack.config.js": """${WEBPACK_CONFIG}""",
        "src/App.js": """${APP_JS}""",
        "src/utils/formatters.js": """${FORMATTERS_JS}"""
    },
    "task_start_time": int(open('/tmp/task_start_time.txt').read().strip()) if os.path.exists('/tmp/task_start_time.txt') else 0,
    "task_end_time": int(os.popen('date +%s').read().strip())
}

with open("$RESULT_FILE", "w") as out:
    json.dump(result, out, indent=2)
PYEXPORT

echo "=== Export Complete ==="