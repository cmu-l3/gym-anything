#!/bin/bash
echo "=== Setting up fix_and_extend_calculator task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/task_result.json /tmp/task_start.png /tmp/task_end.png 2>/dev/null || true
rm -f /tmp/gradle_output.log /tmp/original_hashes.txt 2>/dev/null || true

PROJECT_DIR="/home/ga/AndroidStudioProjects/CalculatorApp"
DATA_SOURCE="/workspace/data/CalculatorApp"
PKG_PATH="com/example/calculator"

rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p /home/ga/AndroidStudioProjects
cp -r "$DATA_SOURCE" "$PROJECT_DIR"
chown -R ga:ga "$PROJECT_DIR"
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;
chmod +x "$PROJECT_DIR/gradlew"

SRC_DIR="$PROJECT_DIR/app/src/main/java/$PKG_PATH"

# =============================================
# BUG 1: Make onPercentPressed crash on zero input
# Remove the null-safe toDoubleOrNull and use toDouble() directly
# =============================================
python3 -c "
import os
path = '$SRC_DIR/CalcActivity.kt'
with open(path, 'r') as f:
    content = f.read()

# Make onPercentPressed unsafe
content = content.replace(
    '''    private fun onPercentPressed() {
        val value = currentInput.toDoubleOrNull() ?: return
        val result = calcEngine.doDiv(value, 100.0)''',
    '''    private fun onPercentPressed() {
        val value = currentInput.toDouble()
        val result = calcEngine.doDiv(value, 100.0)'''
)

# Make onNegatePressed unsafe too
content = content.replace(
    '''    private fun onNegatePressed() {
        val value = currentInput.toDoubleOrNull() ?: return''',
    '''    private fun onNegatePressed() {
        val value = currentInput.toDouble()'''
)

with open(path, 'w') as f:
    f.write(content)
print('Bugs planted in CalcActivity.kt')
"

# Record baselines
{
    echo "ORIG_ACTIVITY_HASH=$(md5sum "$SRC_DIR/CalcActivity.kt" 2>/dev/null | awk '{print $1}')"
    echo "ORIG_ENGINE_HASH=$(md5sum "$SRC_DIR/CalcEngine.kt" 2>/dev/null | awk '{print $1}')"
    echo "ORIG_LAYOUT_HASH=$(md5sum "$PROJECT_DIR/app/src/main/res/layout/activity_calc.xml" 2>/dev/null | awk '{print $1}')"
} > /tmp/original_hashes.txt

date +%s > /tmp/task_start_timestamp

setup_android_studio_project "$PROJECT_DIR" "CalculatorApp" 120
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
