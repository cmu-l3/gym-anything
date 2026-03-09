#!/bin/bash
echo "=== Setting up add_unit_test task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Clean up any previous task artifacts
rm -f /tmp/task_result.json /tmp/task_start.png /tmp/task_end.png 2>/dev/null || true
rm -f /tmp/gradle_output.log /tmp/gradle_test_output.log 2>/dev/null || true
rm -f /tmp/test_report_*.xml 2>/dev/null || true

# Remove any existing NotepadApp project so we start fresh
rm -rf /home/ga/AndroidStudioProjects/NotepadApp 2>/dev/null || true

# Copy the NotepadApp project from data directory
echo "Copying NotepadApp project..."
mkdir -p /home/ga/AndroidStudioProjects
cp -r /workspace/data/NotepadApp /home/ga/AndroidStudioProjects/NotepadApp

# Set correct ownership
chown -R ga:ga /home/ga/AndroidStudioProjects/NotepadApp

# Make gradlew executable
chmod +x /home/ga/AndroidStudioProjects/NotepadApp/gradlew

# Set correct permissions - files 644, directories 755
find /home/ga/AndroidStudioProjects/NotepadApp -type d -exec chmod 755 {} \;
find /home/ga/AndroidStudioProjects/NotepadApp -type f -exec chmod 644 {} \;
chmod +x /home/ga/AndroidStudioProjects/NotepadApp/gradlew

# Ensure the test directory structure exists (but no test files - agent must create them)
TEST_DIR="/home/ga/AndroidStudioProjects/NotepadApp/app/src/test/java/com/example/notepad"
mkdir -p "$TEST_DIR"
chown -R ga:ga /home/ga/AndroidStudioProjects/NotepadApp/app/src/test

echo "Test directory created at: $TEST_DIR"

# Verify no test files exist (clean state for the agent)
EXISTING_TESTS=$(find "$TEST_DIR" -name "*Test.kt" 2>/dev/null | wc -l)
echo "Existing test files in test dir: $EXISTING_TESTS"

# Open the project in Android Studio
setup_android_studio_project "/home/ga/AndroidStudioProjects/NotepadApp" "NotepadApp" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
