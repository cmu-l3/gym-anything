#!/bin/bash
echo "=== Setting up add_comprehensive_unit_tests task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/task_result.json /tmp/task_start.png /tmp/task_end.png 2>/dev/null || true
rm -f /tmp/gradle_output.log /tmp/test_output.log 2>/dev/null || true

PROJECT_DIR="/home/ga/AndroidStudioProjects/FinancialCalcApp"
DATA_SOURCE="/workspace/data/FinancialCalcApp"
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

# Create test directory structure so Android Studio shows it
TEST_DIR="$PROJECT_DIR/app/src/test/java/com/example/financialcalc"
mkdir -p "$TEST_DIR"

chown -R ga:ga "$PROJECT_DIR"
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;
chmod +x "$PROJECT_DIR/gradlew"

date +%s > /tmp/task_start_timestamp

setup_android_studio_project "$PROJECT_DIR" "FinancialCalcApp" 150
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
