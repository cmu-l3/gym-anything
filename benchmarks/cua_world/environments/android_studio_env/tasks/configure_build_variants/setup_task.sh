#!/bin/bash
echo "=== Setting up configure_build_variants task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/task_result.json /tmp/task_start.png /tmp/task_end.png 2>/dev/null || true
rm -f /tmp/gradle_output.log /tmp/original_hashes.txt 2>/dev/null || true

PROJECT_DIR="/home/ga/AndroidStudioProjects/CalculatorApp"
DATA_SOURCE="/workspace/data/CalculatorApp"

rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p /home/ga/AndroidStudioProjects
cp -r "$DATA_SOURCE" "$PROJECT_DIR"
chown -R ga:ga "$PROJECT_DIR"
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;
chmod +x "$PROJECT_DIR/gradlew"

# Record baselines
{
    echo "ORIG_BUILD_HASH=$(md5sum "$PROJECT_DIR/app/build.gradle.kts" 2>/dev/null | awk '{print $1}')"
    echo "FREE_RES_EXISTS=false"
    echo "PREMIUM_RES_EXISTS=false"
} > /tmp/original_hashes.txt

date +%s > /tmp/task_start_timestamp

setup_android_studio_project "$PROJECT_DIR" "CalculatorApp" 120
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
