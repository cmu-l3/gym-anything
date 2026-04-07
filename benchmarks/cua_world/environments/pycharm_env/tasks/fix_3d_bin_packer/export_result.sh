#!/bin/bash
echo "=== Exporting fix_3d_bin_packer Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="fix_3d_bin_packer"
PROJECT_DIR="/home/ga/PycharmProjects/shipping_packer"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Capture final screen
DISPLAY=:1 scrot /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || true

# Run tests
cd "$PROJECT_DIR"
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v 2>&1")
PYTEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)

# --- STATIC ANALYSIS OF FIXES ---

# 1. Check Geometry Fix (Z-axis check)
GEO_FILE="$PROJECT_DIR/packer/geometry.py"
BUG1_FIXED=false
if grep -q "item1.z < item2.z + item2.depth" "$GEO_FILE" 2>/dev/null || \
   grep -q "item1.z < item2.z + item2.height" "$GEO_FILE" 2>/dev/null; then
    # Checking for Z comparison
    BUG1_FIXED=true
fi

# 2. Check Strategy Fix (Volume Descending)
STRAT_FILE="$PROJECT_DIR/packer/strategy.py"
BUG2_FIXED=false
# Should sort by volume (w*h*d) and reverse=True
if grep -q "key=lambda x: x.volume" "$STRAT_FILE" 2>/dev/null && \
   grep -q "reverse=True" "$STRAT_FILE" 2>/dev/null; then
    BUG2_FIXED=true
elif grep -q "key=lambda x:.*_width.*_height.*_depth" "$STRAT_FILE" 2>/dev/null && \
     grep -q "reverse=True" "$STRAT_FILE" 2>/dev/null; then
     BUG2_FIXED=true
fi

# 3. Check Item Fix (Rotation updates dimensions)
ITEM_FILE="$PROJECT_DIR/packer/item.py"
BUG3_FIXED=false
# Check if rotate_xy updates _dim_cache or if dimensions property uses current w/h/d
if grep -q "self._dim_cache =" "$ITEM_FILE" 2>/dev/null; then
    # It seems they updated the cache
    BUG3_FIXED=true
elif grep -q "return (self._width, self._height, self._depth)" "$ITEM_FILE" 2>/dev/null; then
    # They changed property to return live values
    BUG3_FIXED=true
fi

# Also check specific test passes to confirm behavior
TEST_GEO_PASS=false
echo "$PYTEST_OUTPUT" | grep -q "test_rect_intersect_z_stacking PASSED" && TEST_GEO_PASS=true

TEST_ROT_PASS=false
echo "$PYTEST_OUTPUT" | grep -q "test_item_rotation_updates_dimensions PASSED" && TEST_ROT_PASS=true

# Create JSON
cat > "$RESULT_FILE" << EOF
{
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "bug1_fixed": $BUG1_FIXED,
    "bug2_fixed": $BUG2_FIXED,
    "bug3_fixed": $BUG3_FIXED,
    "test_geo_pass": $TEST_GEO_PASS,
    "test_rot_pass": $TEST_ROT_PASS
}
EOF