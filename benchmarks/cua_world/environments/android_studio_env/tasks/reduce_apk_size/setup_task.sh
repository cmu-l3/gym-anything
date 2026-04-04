#!/bin/bash
set -e
echo "=== Setting up reduce_apk_size task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Clean up previous run
rm -rf /tmp/task_result.json 2>/dev/null || true
rm -rf /tmp/task_start.png 2>/dev/null || true
rm -rf /home/ga/AndroidStudioProjects/NewsReaderApp 2>/dev/null || true

# 2. Prepare the project
# We use CalculatorApp as a base because it's a valid compiling project, 
# then rename it to simulate the NewsReaderApp context.
echo "Creating project..."
mkdir -p /home/ga/AndroidStudioProjects
if [ -d "/workspace/data/CalculatorApp" ]; then
    cp -r /workspace/data/CalculatorApp /home/ga/AndroidStudioProjects/NewsReaderApp
else
    # Fallback if specific data not found (shouldn't happen in this env, but good for robustness)
    echo "ERROR: Base project data not found!"
    exit 1
fi

PROJECT_DIR="/home/ga/AndroidStudioProjects/NewsReaderApp"

# 3. Rename project in settings.gradle.kts to match task description
SETTINGS_FILE="$PROJECT_DIR/settings.gradle.kts"
if [ -f "$SETTINGS_FILE" ]; then
    sed -i 's/rootProject.name = "CalculatorApp"/rootProject.name = "NewsReaderApp"/' "$SETTINGS_FILE"
fi
# Handle Groovy DSL case just in case
SETTINGS_FILE_GROOVY="$PROJECT_DIR/settings.gradle"
if [ -f "$SETTINGS_FILE_GROOVY" ]; then
    sed -i "s/rootProject.name = 'CalculatorApp'/rootProject.name = 'NewsReaderApp'/" "$SETTINGS_FILE_GROOVY"
fi

# 4. Inject BLOAT file
# Create a 30MB dummy file in assets
ASSETS_DIR="$PROJECT_DIR/app/src/main/assets"
mkdir -p "$ASSETS_DIR"
BLOAT_FILE="$ASSETS_DIR/onboarding_deprecated.mp4"

echo "Injecting 30MB bloat file at $BLOAT_FILE..."
# Use dd to create a file of zeros (compressible, but APKs don't compress assets by default usually)
# Better: use /dev/urandom for uncompressible data to ensure APK stays large
dd if=/dev/urandom of="$BLOAT_FILE" bs=1M count=30 status=progress

# 5. Set ownership
chown -R ga:ga "$PROJECT_DIR"
chmod +x "$PROJECT_DIR/gradlew"

# 6. Pre-build to ensure gradle cache is warm and APK exists (inflated state)
echo "Pre-building project (this may take a minute)..."
cd "$PROJECT_DIR"
su - ga -c "export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; ./gradlew assembleDebug --no-daemon"

# 7. Open Android Studio
setup_android_studio_project "$PROJECT_DIR" "NewsReaderApp" 180

# 8. Record initial state
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="