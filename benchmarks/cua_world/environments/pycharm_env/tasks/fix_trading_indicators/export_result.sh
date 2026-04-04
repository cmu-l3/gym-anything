#!/bin/bash
echo "=== Exporting fix_trading_indicators Result ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="fix_trading_indicators"
PROJECT_DIR="/home/ga/PycharmProjects/trading_indicators"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || true

PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v --tb=short 2>&1")
PYTEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
ALL_TESTS_PASS=false
[ "$PYTEST_EXIT_CODE" -eq 0 ] && ALL_TESTS_PASS=true

# Bug 1: EMA smoothing factor fix (check for 2/(period+1) pattern)
BUG1_FIXED=false
if grep -qE 'k\s*=\s*2\s*/\s*\(.*period.*\+.*1\)|k\s*=\s*2\.0\s*/\s*\(' "$PROJECT_DIR/indicators/ema.py" 2>/dev/null; then
    BUG1_FIXED=true
fi
echo "$PYTEST_OUTPUT" | grep -q "test_ema_first_value_after_seed PASSED" && BUG1_FIXED=true
echo "$PYTEST_OUTPUT" | grep -q "test_ema_converges_toward_prices PASSED" && BUG1_FIXED=true

# Bug 2: RSI RS formula fix (check for division not subtraction)
BUG2_FIXED=false
RSI_CONTENT=$(cat "$PROJECT_DIR/indicators/rsi.py" 2>/dev/null || echo "")
# Check for division pattern in RS calculation, not subtraction
if echo "$RSI_CONTENT" | grep -q 'rs\s*=\s*ag\s*/\s*al\|rs\s*=\s*avg_gain\s*/\s*avg_loss'; then
    BUG2_FIXED=true
fi
# Also accept if the division is inline
if echo "$RSI_CONTENT" | grep -qE 'ag\s*/\s*al|avg_gain\s*/\s*avg_loss'; then
    BUG2_FIXED=true
fi
echo "$PYTEST_OUTPUT" | grep -q "test_rsi_range_valid PASSED" && BUG2_FIXED=true
echo "$PYTEST_OUTPUT" | grep -q "test_rsi_all_gains_returns_100 PASSED" && BUG2_FIXED=true

# Bug 3: Sharpe ratio divides by std dev not variance
# Note: unfixed code already uses math.sqrt(252), so check specifically for sqrt(variance)
BUG3_FIXED=false
STATS_CONTENT=$(cat "$PROJECT_DIR/indicators/stats.py" 2>/dev/null || echo "")
if echo "$STATS_CONTENT" | grep -qE 'sqrt\(variance\)|math\.sqrt\(variance|std_dev\s*=\s*math\.sqrt|std_dev\s*=\s*\('; then
    BUG3_FIXED=true
fi
echo "$PYTEST_OUTPUT" | grep -q "test_sharpe_reasonable_magnitude PASSED" && BUG3_FIXED=true
echo "$PYTEST_OUTPUT" | grep -q "test_sharpe_known_value PASSED" && BUG3_FIXED=true

# Bug 4: Max drawdown uses global running peak
BUG4_FIXED=false
if echo "$STATS_CONTENT" | grep -qE 'running_max|peak\s*=\s*max\(peak|peak\s*=\s*prices\[0\]|if prices\[i\] > peak'; then
    BUG4_FIXED=true
fi
echo "$PYTEST_OUTPUT" | grep -q "test_max_drawdown_known_value PASSED" && BUG4_FIXED=true
echo "$PYTEST_OUTPUT" | grep -q "test_max_drawdown_immediate_drop PASSED" && BUG4_FIXED=true

cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "all_tests_pass": $ALL_TESTS_PASS,
    "bug1_ema_smoothing_fixed": $BUG1_FIXED,
    "bug2_rsi_rs_formula_fixed": $BUG2_FIXED,
    "bug3_sharpe_stddev_fixed": $BUG3_FIXED,
    "bug4_drawdown_running_peak_fixed": $BUG4_FIXED
}
EOF

echo "Pytest: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "Bug 1 (EMA k) fixed: $BUG1_FIXED"
echo "Bug 2 (RSI RS) fixed: $BUG2_FIXED"
echo "Bug 3 (Sharpe) fixed: $BUG3_FIXED"
echo "Bug 4 (Drawdown) fixed: $BUG4_FIXED"
echo "=== Export Complete ==="
