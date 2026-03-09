#!/bin/bash
echo "=== Setting up refactor_rename_class task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Clean up any previous task artifacts
rm -rf /tmp/task_result.json 2>/dev/null || true
rm -rf /tmp/task_start.png /tmp/task_end.png 2>/dev/null || true
rm -rf /tmp/gradle_output.log 2>/dev/null || true
rm -rf /tmp/original_calcengine_hash.txt 2>/dev/null || true
rm -rf /tmp/original_calcactivity_hash.txt 2>/dev/null || true

# Remove any existing CalculatorApp project so we start fresh
rm -rf /home/ga/AndroidStudioProjects/CalculatorApp 2>/dev/null || true

# Copy the CalculatorApp project from data
echo "Copying CalculatorApp project..."
cp -r /workspace/data/CalculatorApp /home/ga/AndroidStudioProjects/CalculatorApp

# Set ownership and permissions
chown -R ga:ga /home/ga/AndroidStudioProjects/CalculatorApp
find /home/ga/AndroidStudioProjects/CalculatorApp -type d -exec chmod 755 {} \;
find /home/ga/AndroidStudioProjects/CalculatorApp -type f -exec chmod 644 {} \;
chmod +x /home/ga/AndroidStudioProjects/CalculatorApp/gradlew

# Record hashes of original files for change detection
CALC_ENGINE_PATH="/home/ga/AndroidStudioProjects/CalculatorApp/app/src/main/java/com/example/calculator/CalcEngine.kt"
CALC_ACTIVITY_PATH="/home/ga/AndroidStudioProjects/CalculatorApp/app/src/main/java/com/example/calculator/CalcActivity.kt"

if [ -f "$CALC_ENGINE_PATH" ]; then
    md5sum "$CALC_ENGINE_PATH" > /tmp/original_calcengine_hash.txt
    echo "Recorded original CalcEngine.kt hash"
fi

if [ -f "$CALC_ACTIVITY_PATH" ]; then
    md5sum "$CALC_ACTIVITY_PATH" > /tmp/original_calcactivity_hash.txt
    echo "Recorded original CalcActivity.kt hash"
fi

# Open the project in Android Studio
setup_android_studio_project "/home/ga/AndroidStudioProjects/CalculatorApp" "CalculatorApp" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
