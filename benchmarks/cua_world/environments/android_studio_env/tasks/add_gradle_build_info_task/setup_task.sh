#!/bin/bash
set -e
echo "=== Setting up add_gradle_build_info_task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Project Paths
PROJECT_DIR="/home/ga/AndroidStudioProjects/SunflowerApp"
DATA_SOURCE="/workspace/data/SunflowerApp"

# 1. Prepare Project
echo "Setting up SunflowerApp..."
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p /home/ga/AndroidStudioProjects
cp -r "$DATA_SOURCE" "$PROJECT_DIR"

# 2. Configure Git (Required for gitCommitHash requirement)
echo "Configuring Git repo..."
cd "$PROJECT_DIR"
# Remove existing git if any to start fresh
rm -rf .git
git init
git config user.email "ga@example.com"
git config user.name "GA User"
git add .
git commit -m "Initial commit for SunflowerApp"

# 3. Modify build.gradle.kts to known state
# We enforce specific versions to verify against later
BUILD_FILE="$PROJECT_DIR/app/build.gradle.kts"
echo "Configuring build.gradle.kts..."

# Use sed/cat to inject specific version config if not present, 
# or just overwrite the relevant section if we know the structure.
# For robustness, we'll append/modify the android block.
# Ideally, the data source already has a structure we can manipulate.
# Here we ensure values match the task description.

# We will read the file and replace values or ensure they exist.
# Since parsing KTS with sed is fragile, we'll trust the base project 
# but double check specific lines or append them if missing.
# For this task, we assume the base Sunflower project structure.

# Let's ensure the values are set as expected by the verifier
# We'll just modify the defaultConfig block
sed -i 's/versionCode = .*/versionCode = 1/' "$BUILD_FILE"
sed -i 's/versionName = .*/versionName = "1.0.0"/' "$BUILD_FILE"
sed -i 's/minSdk = .*/minSdk = 24/' "$BUILD_FILE"
sed -i 's/targetSdk = .*/targetSdk = 34/' "$BUILD_FILE"

# 4. Clean up target output location
ASSETS_DIR="$PROJECT_DIR/app/src/main/assets"
rm -f "$ASSETS_DIR/build-info.json" 2>/dev/null || true

# 5. Set Permissions
chown -R ga:ga "$PROJECT_DIR"
chmod +x "$PROJECT_DIR/gradlew"

# 6. Open Project in Android Studio
setup_android_studio_project "$PROJECT_DIR" "SunflowerApp" 180

# 7. Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="