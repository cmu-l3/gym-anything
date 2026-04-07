#!/bin/bash
echo "=== Exporting debug_concurrent_cache Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="debug_concurrent_cache"
PROJECT_DIR="/home/ga/PycharmProjects/concurrent_cache"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check for Test Modifications (Anti-Gaming)
CURRENT_MD5=$(find "$PROJECT_DIR/tests" -type f -exec md5sum {} \; | sort)
ORIGINAL_MD5=$(cat /tmp/tests_checksum.md5)
TESTS_MODIFIED=false

if [ "$CURRENT_MD5" != "$ORIGINAL_MD5" ]; then
    TESTS_MODIFIED=true
    echo "WARNING: Tests were modified!"
fi

# 3. Run Verification Tests
# We run the tests and capture verbose output to parse individual test statuses
echo "Running validation tests..."
# Use timeout to prevent hanging on unfixed deadlocks
PYTEST_OUT=$(su - ga -c "cd $PROJECT_DIR && python3 -m pytest tests/ -v --timeout=10 2>&1")
EXIT_CODE=$?

# 4. Parse Test Results
TESTS_TOTAL=$(echo "$PYTEST_OUT" | grep -c "tests/test_")
TESTS_PASSED=$(echo "$PYTEST_OUT" | grep "PASSED" | wc -l)
TESTS_FAILED=$(echo "$PYTEST_OUT" | grep "FAILED" | wc -l)
TESTS_ERRORS=$(echo "$PYTEST_OUT" | grep "ERROR" | wc -l)

# Check specific critical tests
PASS_BUG1=$(echo "$PYTEST_OUT" | grep "test_concurrent_eviction_integrity PASSED" | wc -l)
PASS_BUG2=$(echo "$PYTEST_OUT" | grep "test_deadlock_resize_put PASSED" | wc -l)
PASS_BUG3=$(echo "$PYTEST_OUT" | grep "test_concurrent_stats_accuracy PASSED" | wc -l)
PASS_BUG4=$(echo "$PYTEST_OUT" | grep "test_ttl_update_race PASSED" | wc -l)

# 5. Code Pattern Analysis (Static Verification of Fixes)
# Read source files
LRU_SRC=$(cat "$PROJECT_DIR/cache/lru_cache.py" 2>/dev/null)
TTL_SRC=$(cat "$PROJECT_DIR/cache/ttl_cache.py" 2>/dev/null)

# Bug 1: Eviction inside lock?
# We look for `with self._lock:` ... `_evict_oldest()` inside the block
# Or `should_evict` check and call all indented inside lock
# Simplified regex check: check if _evict_oldest call is indented under the lock block
# This is tricky with regex, so we'll rely heavily on the test passing, 
# but we can check if the naive buggy pattern "if should_evict:\n\s+self._evict_oldest()" exists at top level indentation relative to method
# Actually, strict anti-gaming: check if `self._evict_oldest()` appears inside `put`.
# If they removed the method entirely, that's valid too if tests pass.
# We'll trust the tests primarily, but check file hash changed to ensure work was done.
LRU_CHANGED=$(stat -c %Y "$PROJECT_DIR/cache/lru_cache.py")
TTL_CHANGED=$(stat -c %Y "$PROJECT_DIR/cache/ttl_cache.py")
FILES_MODIFIED=false
if [ "$LRU_CHANGED" -gt "$START_TIME" ] || [ "$TTL_CHANGED" -gt "$START_TIME" ]; then
    FILES_MODIFIED=true
fi

# 6. JSON Export
cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "timestamp": "$(date -Iseconds)",
    "pytest_exit_code": $EXIT_CODE,
    "tests_total": $TESTS_TOTAL,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "tests_errors": $TESTS_ERRORS,
    "pass_bug1_eviction": $((PASS_BUG1 > 0 ? "true" : "false")),
    "pass_bug2_deadlock": $((PASS_BUG2 > 0 ? "true" : "false")),
    "pass_bug3_stats": $((PASS_BUG3 > 0 ? "true" : "false")),
    "pass_bug4_toctou": $((PASS_BUG4 > 0 ? "true" : "false")),
    "tests_modified": $TESTS_MODIFIED,
    "source_files_modified": $FILES_MODIFIED
}
EOF

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="