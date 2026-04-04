#!/bin/bash
set -e

echo "=== Setting up configure_staging_build_type task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up previous artifacts
rm -rf /tmp/task_result.json /tmp/gradle_build_output.log 2>/dev/null || true
rm -rf /home/ga/AndroidStudioProjects/Unscramble 2>/dev/null || true

# Prepare the project
# We use the official Google Unscramble app starter code
PROJECT_DIR="/home/ga/AndroidStudioProjects/Unscramble"
echo "Cloning Unscramble app..."
mkdir -p /home/ga/AndroidStudioProjects
# Clone the repository
git clone --depth 1 https://github.com/google-developer-training/android-basics-kotlin-unscramble-app.git "$PROJECT_DIR" 2>/dev/null || {
    echo "Git clone failed, using backup zip if available or failing..."
    # Fallback logic could go here, but for now we assume internet access or pre-cached data
}

# Ensure ownership
chown -R ga:ga "$PROJECT_DIR"
chmod +x "$PROJECT_DIR/gradlew"

# Open the project in Android Studio
setup_android_studio_project "$PROJECT_DIR" "Unscramble" 180

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="